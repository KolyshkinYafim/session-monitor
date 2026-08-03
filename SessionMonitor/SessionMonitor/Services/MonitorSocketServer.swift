import Foundation
import Darwin

/// Unix-domain socket server for blocking hook RPCs (PermissionRequest).
/// Protocol: one NDJSON line request, one NDJSON line response.
///
/// Request:
///   {"v":1,"source":"claude","event":"PermissionRequest","sessionId":"…","requestId":"…","summary":"…","payload":{…}}
/// Response:
///   {"decision":{"behavior":"allow"|"deny"}}
///
/// Fail-open in both directions: if the app is down the hook exits 0 with no stdout,
/// and if the hook dies while we hold it the card stops waiting instead of hanging.
@MainActor
final class MonitorSocketServer {
    private let store: SessionStore
    private let path: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    /// requestId → pending client awaiting a decision
    private var pending: [String: Pending] = [:]
    private var reaper: Timer?

    /// A hook that has been waiting this long is almost certainly gone (Claude killed,
    /// terminal closed without EOF reaching us). Drop it so the island stays honest.
    private static let pendingTTL: TimeInterval = 6 * 3600

    private struct Pending {
        var clientFD: Int32
        var sessionId: String
        var summary: String
        var createdAt: Date
    }

    /// Bookkeeping only — the bytes live on the reader thread that owns the descriptor.
    private final class Client {}

    /// The app runs exactly one server; reader threads hop back to it through this
    /// instead of capturing `self` in a @Sendable closure.
    private static weak var current: MonitorSocketServer?

    /// `SESSION_MONITOR_DEBUG=1` traces the hook conversation to stderr — the only way
    /// to see why a permission never reached the island without attaching a debugger.
    nonisolated static let debugLog = ProcessInfo.processInfo.environment["SESSION_MONITOR_DEBUG"] == "1"

    private func trace(_ message: String) {
        Self.traceRaw(message)
    }

    /// Callable from the reader threads too, hence nonisolated.
    nonisolated static func traceRaw(_ message: String) {
        guard debugLog else { return }
        FileHandle.standardError.write(Data("[socket] \(message)\n".utf8))
    }

    init(store: SessionStore, path: URL = BridgePath.socketFile) {
        self.store = store
        self.path = path.path
    }

    func start() {
        stop()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Stale socket from a previous crash.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout.size(ofValue: on)))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathC = path.cString(using: .utf8) ?? []
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathC.count <= maxPath else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { sunPath in
            guard let base = sunPath.baseAddress else { return }
            pathC.withUnsafeBytes { src in
                if let s = src.baseAddress {
                    memcpy(base, s, pathC.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            unlink(path)
            return
        }

        // Owner-only: hooks run as the same user, nobody else needs in.
        chmod(path, 0o600)

        // Non-blocking is not optional here: the read source fires again while the
        // handler is still running, and a second blocking accept() would park the
        // main thread forever — taking the whole UI and every main-queue hop with it.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        listenFD = fd
        Self.current = self
        trace("listening at \(path)")
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler {
            MainActor.assumeIsolated {
                MonitorSocketServer.current?.acceptClients()
            }
        }
        acceptSource = src
        src.resume()

        reaper = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reapStalePending() }
        }
    }

    func stop() {
        reaper?.invalidate()
        reaper = nil
        // Wake every parked reader; each closes its own descriptor on the way out.
        for fd in clients.keys {
            shutdown(fd, SHUT_RDWR)
        }
        clients.removeAll()
        pending.removeAll()
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    /// Called from UI when the user taps Allow / Deny (or free-text that maps to allow).
    @discardableResult
    func resolve(requestId: String, allow: Bool) -> Bool {
        guard let item = pending.removeValue(forKey: requestId) else { return false }
        let behavior = allow ? "allow" : "deny"
        let sent = writeLine(fd: item.clientFD, #"{"decision":{"behavior":"\#(behavior)"}}"#)
        trace("resolve \(requestId) → \(behavior) sent=\(sent)")
        dropClient(fd: item.clientFD)
        return sent
    }

    /// True while a hook is still holding the line for this request.
    func isPending(requestId: String) -> Bool {
        pending[requestId] != nil
    }

    // MARK: - Accept / read

    /// Drain the backlog until EAGAIN — one source event can cover several connections.
    private func acceptClients() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { return }
            adopt(clientFD: clientFD)
        }
    }

    private func adopt(clientFD: Int32) {
        trace("accepted fd \(clientFD)")

        // The listener is non-blocking; BSD hands that flag down to accepted sockets and
        // the reader thread below wants a plain blocking read.
        let clientFlags = fcntl(clientFD, F_GETFL, 0)
        _ = fcntl(clientFD, F_SETFL, clientFlags & ~O_NONBLOCK)

        // Without this, writing to a hook that already died raises SIGPIPE and kills the app.
        var nosigpipe: Int32 = 1
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &nosigpipe,
            socklen_t(MemoryLayout.size(ofValue: nosigpipe))
        )

        clients[clientFD] = Client()
        // One blocking reader per connection. A dispatch read source on the accepted
        // descriptor never fired here, and a permission hook holds its connection for
        // hours — a parked thread is both simpler and cheap at this concurrency.
        DispatchQueue.global(qos: .utility).async {
            Self.traceRaw("reader started for fd \(clientFD)")
            var buffer = Data()
            var buf = [UInt8](repeating: 0, count: 16_384)
            while true {
                let n = read(clientFD, &buf, buf.count)
                Self.traceRaw("read \(n) bytes on fd \(clientFD)")
                if n <= 0 {
                    if n < 0, errno == EINTR { continue }
                    break
                }
                buffer.append(contentsOf: buf[0..<n])
                while let range = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            MonitorSocketServer.current?.handleLine(fd: clientFD, data: lineData)
                        }
                    }
                }
            }
            // EOF / error — the hook is gone. Release any card it was holding so the
            // island doesn't show a permission nobody can answer any more.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MonitorSocketServer.current?.trace("eof on fd \(clientFD)")
                    MonitorSocketServer.current?.dropClient(fd: clientFD, releasePending: true)
                }
            }
            // The reader owns the descriptor: closing it anywhere else could yank an fd
            // number out from under this thread and land a later client on the same one.
            close(clientFD)
        }
    }

    private func handleLine(fd: Int32, data: Data) {
        trace("line: \(String(data: data.prefix(120), encoding: .utf8) ?? "?")")
        // The reader hops here asynchronously: if the hook already died, registering a
        // pending request against its dead descriptor would strand the card forever.
        guard clients[fd] != nil else {
            trace("dropping line for closed fd \(fd)")
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            dropClient(fd: fd)
            return
        }

        // Plain SessionEvent (`{"type":"session.upsert",…}`) — the same shape the JSONL
        // bridge speaks, so agents without a hook protocol (OpenCode plugin, watchers)
        // can push straight into the island without a file in between.
        if let type = obj["type"] as? String {
            if let event = SessionEventCodec.event(from: data) {
                store.apply(event)
                trace("applied \(type) — \(store.sessions.count) session(s) known")
            } else {
                trace("rejected \(type) — shape didn't match the event contract")
            }
            _ = writeLine(fd: fd, "{\"ok\":true}")
            dropClient(fd: fd)
            return
        }

        guard let event = obj["event"] as? String else {
            // Unknown noise — close quietly.
            dropClient(fd: fd)
            return
        }

        if event == "PermissionRequest" {
            let payload = obj["payload"] as? [String: Any]
            let sessionId = (obj["sessionId"] as? String)
                ?? payload?["session_id"] as? String
                ?? "unknown"
            let requestId = (obj["requestId"] as? String)
                ?? "\(sessionId)-\(Int(Date().timeIntervalSince1970 * 1000))"
            let summary = (obj["summary"] as? String)
                ?? permissionSummary(from: payload)
                ?? "Needs permission"

            pending[requestId] = Pending(
                clientFD: fd,
                sessionId: sessionId,
                summary: summary,
                createdAt: Date()
            )

            // Surface in island as a waiting permission card.
            store.apply(
                .permission(id: sessionId, requestId: requestId, summary: summary)
            )
            // Dev/E2E only: prove the full round-trip without a human click.
            // `SESSION_MONITOR_AUTO_APPROVE=allow|deny` — never a shipped default.
            switch ProcessInfo.processInfo.environment["SESSION_MONITOR_AUTO_APPROVE"] {
            case "1", "allow": resolve(requestId: requestId, allow: true)
            case "deny": resolve(requestId: requestId, allow: false)
            default: break
            }
            // Keep connection open until resolve().
            return
        }

        // Fire-and-forget events over the socket (optional path). Ack and close.
        _ = writeLine(fd: fd, "{\"ok\":true}")
        dropClient(fd: fd)
    }

    private func permissionSummary(from payload: [String: Any]?) -> String? {
        guard let payload else { return nil }
        if let toolInput = payload["tool_input"] as? [String: Any] {
            if let cmd = toolInput["command"] as? String, !cmd.isEmpty {
                return "Run: \(String(cmd.prefix(90)))"
            }
            if let file = toolInput["file_path"] as? String, !file.isEmpty {
                let name = (file as NSString).lastPathComponent
                let tool = payload["tool_name"] as? String ?? "Edit"
                return "\(tool) \(name)?"
            }
        }
        if let tool = payload["tool_name"] as? String, !tool.isEmpty {
            return "Allow \(tool)?"
        }
        if let msg = payload["message"] as? String, !msg.isEmpty {
            return String(msg.prefix(120))
        }
        return nil
    }

    // MARK: - Plumbing

    /// Writes one NDJSON line, tolerating partial writes. Never raises SIGPIPE
    /// (SO_NOSIGPIPE is set on accept); a dead peer just returns false.
    @discardableResult
    private func writeLine(fd: Int32, _ line: String) -> Bool {
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                return write(fd, base, buf.count)
            }
            if written <= 0 {
                if written < 0, errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }

    /// Ends a conversation and forgets it. `releasePending` also clears the island card,
    /// which is what we want on EOF but not after a user decision (already applied).
    /// Only shuts the socket down — the reader thread does the actual close.
    private func dropClient(fd: Int32, releasePending: Bool = false) {
        let known = clients.removeValue(forKey: fd) != nil
        let orphaned = pending.filter { $0.value.clientFD == fd }
        pending = pending.filter { $0.value.clientFD != fd }
        if releasePending {
            for (requestId, item) in orphaned {
                store.cancelPending(sessionId: item.sessionId, requestId: requestId)
            }
        }
        if known { shutdown(fd, SHUT_RDWR) }
    }

    private func reapStalePending() {
        let cutoff = Date().addingTimeInterval(-Self.pendingTTL)
        let stale = pending.filter { $0.value.createdAt < cutoff }
        guard !stale.isEmpty else { return }
        for (requestId, item) in stale {
            pending.removeValue(forKey: requestId)
            store.cancelPending(sessionId: item.sessionId, requestId: requestId)
            dropClient(fd: item.clientFD)
        }
    }
}
