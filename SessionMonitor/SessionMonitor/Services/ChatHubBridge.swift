import Darwin
import Foundation

@MainActor
final class ChatHubBridge {
    private let store: SessionStore
    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var rotateTimer: Timer?
    private var fileHandle: FileHandle?
    private var buffer = Data()
    private var started = false
    private var replaying = false

    init(store: SessionStore, fileURL: URL = BridgePath.eventsFile) {
        self.store = store
        self.fileURL = fileURL
    }

    var path: String { fileURL.path }

    func start() {
        guard !started else { return }
        started = true
        ensureFile()
        withReplay { drain() }
        startWatching()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drain()
            }
        }
        // Producers (hooks, Chat Hub) only ever append — trimming lives here, in the one
        // process that can also fix its own read offset afterwards.
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rotateIfNeeded()
            }
        }
        rotateIfNeeded()
    }

    func stop() {
        started = false
        pollTimer?.invalidate()
        pollTimer = nil
        rotateTimer?.invalidate()
        rotateTimer = nil
        source?.cancel()
        source = nil
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func ensureFile() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        }
    }

    private func startWatching() {
        let path = fileURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.onFileSystemEvent()
            }
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()
    }

    /// Rename/delete (e.g. external trim) invalidates the open handle — `drain` notices the
    /// swap and reopens, which also re-arms the watch on the inode that now owns the path.
    private func onFileSystemEvent() {
        guard started else { return }
        drain()
        // If drain failed and closed the handle, re-arm the watch on the new inode.
        if fileHandle == nil {
            reopenHandle()
            drain()
        }
    }

    private func reopenHandle() {
        try? fileHandle?.close()
        fileHandle = nil
        buffer = Data()
        source?.cancel()
        source = nil
        // O_EVTONLY on a path that does not exist yet fails silently and leaves us with no
        // watch for the rest of the process lifetime, so recreate the file first.
        ensureFile()
        startWatching()
    }

    private func drain() {
        guard started else { return }
        ensureFile()
        if let handle = fileHandle, isHandleStale(handle) {
            reopenHandle()
            // The replacement is read from byte 0, i.e. history again — same rules as the
            // startup replay, or a rotation would re-fire every notification in the tail.
            withReplay { readAvailable() }
            return
        }
        readAvailable()
    }

    private func readAvailable() {
        do {
            if fileHandle == nil {
                fileHandle = try FileHandle(forReadingFrom: fileURL)
            }
            guard let handle = fileHandle else { return }
            if let data = try handle.readToEnd(), !data.isEmpty {
                buffer.append(data)
                flushLines()
            }
        } catch {
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    /// Another writer rotating the file (`mv` + recreate, logrotate, `cp` over the path)
    /// puts a new inode behind the same name. Our handle would keep reading the orphan and
    /// return zero bytes forever — no error, the island just goes deaf.
    private func isHandleStale(_ handle: FileHandle) -> Bool {
        guard let live = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        else { return false }
        var held = Darwin.stat()
        guard fstat(handle.fileDescriptor, &held) == 0 else { return true }
        if let inode = (live[.systemFileNumber] as? NSNumber)?.uint64Value,
           inode != UInt64(held.st_ino) {
            return true
        }
        if let device = (live[.systemNumber] as? NSNumber)?.int32Value,
           device != Int32(held.st_dev) {
            return true
        }
        // Truncated behind our back: our offset sits past EOF, so nothing new ever arrives.
        let size = (live[.size] as? NSNumber)?.uint64Value ?? 0
        return size < ((try? handle.offset()) ?? 0)
    }

    /// History must not reach the notification/sound handler, and must not stamp live
    /// timestamps on sessions that ended days ago.
    private func withReplay(_ body: () -> Void) {
        replaying = true
        store.beginReplay()
        body()
        store.endReplay()
        replaying = false
    }

    /// Trim the append-only bridge in place: same inode, so hooks holding an O_APPEND
    /// descriptor keep working, and the shared lock keeps a concurrent append from
    /// landing in the bytes we are about to drop.
    ///
    /// `flock` alone was not enough: Chat Hub is a Node process and Node exposes no
    /// `flock` (`fs.constants.O_EXLOCK` is undefined), so its appends never joined the
    /// lock and a trim could silently eat them. The one primitive Swift, Node and the
    /// Python hooks all have is an exclusive create of a sibling `.lock` file — the
    /// protocol lives in docs/bridge.md and must change on all three sides at once.
    private func rotateIfNeeded() {
        guard started else { return }
        let path = fileURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard size > Self.maxBridgeBytes else { return }

        // Fail closed here, unlike the writers: an un-lockable trim is skipped and
        // retried later, because trimming is the only thing that can destroy data.
        guard acquireBridgeLock() else { return }
        defer { releaseBridgeLock() }

        guard let handle = try? FileHandle(forUpdating: fileURL),
              let data = try? handle.readToEnd()
        else { return }
        defer { try? handle.close() }

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard lines.count > Self.keepLines else { return }
        var tail = Data()
        for line in lines.suffix(Self.keepLines) where !line.isEmpty {
            tail.append(contentsOf: line)
            tail.append(0x0A)
        }
        do {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: tail)
            try handle.synchronize()
        } catch {
            return
        }
        // Our reader's offset now points past the end — re-anchor it so appends that
        // land after the trim are still picked up.
        buffer = Data()
        try? fileHandle?.seek(toOffset: UInt64(tail.count))
    }

    private static let maxBridgeBytes = 2_000_000
    private static let keepLines = 1_500

    // Shared with Chat Hub's src/main/bridge-lock.ts — same path, same staleness
    // window, same fail-open rule. See docs/bridge.md.
    private static let lockStaleSeconds: TimeInterval = 5
    private static let lockWaitSeconds: TimeInterval = 1.5
    private var lockURL: URL { fileURL.appendingPathExtension("lock") }

    private func acquireBridgeLock() -> Bool {
        let deadline = Date().addingTimeInterval(Self.lockWaitSeconds)
        repeat {
            // O_CREAT|O_EXCL is the whole lock: atomic, and the one thing Node's
            // `open(path, "wx")` and Python's `os.O_EXCL` express identically.
            let fd = open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                return true
            }
            breakStaleBridgeLock()
            Thread.sleep(forTimeInterval: 0.025)
        } while Date() < deadline
        return false
    }

    private func releaseBridgeLock() {
        try? FileManager.default.removeItem(at: lockURL)
    }

    /// A process killed mid-trim would otherwise wedge the bridge forever.
    private func breakStaleBridgeLock() {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: lockURL.path),
            let modified = attrs[.modificationDate] as? Date,
            Date().timeIntervalSince(modified) > Self.lockStaleSeconds
        else { return }
        try? FileManager.default.removeItem(at: lockURL)
    }

    private func flushLines() {
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            if let parsed = SessionEventCodec.timedEvent(fromLine: line) {
                store.apply(normalizeReplay(parsed.event), at: parsed.at ?? Date())
            }
        }
    }

    private func normalizeReplay(_ event: SessionEvent) -> SessionEvent {
        guard replaying else { return event }
        switch event {
        case .status(let id, .running), .status(let id, .waitingInput):
            return .status(id: id, status: .idle)
        case .upsert(var session) where session.status == .running || session.status == .waitingInput:
            session.status = .idle
            return .upsert(session)
        case .permission(let id, _, _), .question(let id, _, _, _):
            return .status(id: id, status: .idle)
        default:
            return event
        }
    }
}

/// One place that understands the JSONL/socket event shapes, so the file bridge and
/// the socket server can never drift apart on what a `session.upsert` looks like.
enum SessionEventCodec {
    static func event(from data: Data) -> SessionEvent? {
        guard let line = String(data: data, encoding: .utf8) else { return nil }
        return event(fromLine: line)
    }

    static func event(fromLine line: String) -> SessionEvent? {
        timedEvent(fromLine: line)?.event
    }

    /// `at` is the producer's own `ts`. Replaying a week-old file without it would stamp
    /// every session with wall-clock now and make all of them look freshly active.
    static func timedEvent(fromLine line: String) -> (event: SessionEvent, at: Date?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }
        let at = date(from: obj["ts"])
        guard let event = event(type: type, obj: obj) else { return nil }
        return (event, at)
    }

    private static func event(type: String, obj: [String: Any]) -> SessionEvent? {
        switch type {
        case "session.upsert":
            guard let sessionObj = obj["session"] as? [String: Any],
                  let meta = session(sessionObj)
            else { return nil }
            return .upsert(meta)
        case "session.status":
            guard let id = obj["id"] as? String,
                  let statusRaw = obj["status"] as? String,
                  let status = SessionStatus(rawValue: statusRaw)
            else { return nil }
            return .status(id: id, status: status)
        case "session.ended":
            guard let id = obj["id"] as? String,
                  let reasonRaw = obj["reason"] as? String,
                  let reason = SessionEvent.EndReason(rawValue: reasonRaw)
            else { return nil }
            return .ended(id: id, reason: reason)
        case "session.permission":
            guard let id = obj["id"] as? String,
                  let requestId = obj["requestId"] as? String,
                  let summary = obj["summary"] as? String
            else { return nil }
            return .permission(id: id, requestId: requestId, summary: summary)
        case "session.question":
            guard let id = obj["id"] as? String,
                  let requestId = obj["requestId"] as? String,
                  let prompt = obj["prompt"] as? String
            else { return nil }
            let options = obj["options"] as? [String]
            return .question(id: id, requestId: requestId, prompt: prompt, options: options)
        case "session.message":
            guard let id = obj["id"] as? String,
                  let role = obj["role"] as? String,
                  let preview = obj["preview"] as? String
            else { return nil }
            return .message(id: id, role: role, preview: preview)
        default:
            return nil
        }
    }

    static func session(_ obj: [String: Any]) -> SessionMeta? {
        guard let id = obj["id"] as? String,
              let title = obj["title"] as? String,
              let provider = obj["provider"] as? String,
              let statusRaw = obj["status"] as? String,
              let status = SessionStatus(rawValue: statusRaw)
        else { return nil }

        let cwd = obj["cwd"] as? String
        let project = obj["project"] as? String
        let model = obj["model"] as? String
        let lastActivity = obj["lastActivity"] as? String ?? obj["activity"] as? String
        let focusApp = obj["focusApp"] as? String
        let tty = obj["tty"] as? String
        let termSession = obj["termSession"] as? String
        let termIds = obj["termIds"] as? [String: String]
        let sourceRaw = obj["source"] as? String
        let source = sourceRaw.flatMap(SessionSource.init(rawValue:)) ?? .unknown
        let updatedAt = date(from: obj["updatedAt"]) ?? Date()
        let createdAt = date(from: obj["createdAt"]) ?? updatedAt
        let endedAt = date(from: obj["endedAt"])
        return SessionMeta(
            id: id,
            title: title,
            provider: provider,
            project: project,
            cwd: cwd,
            model: model,
            status: status,
            updatedAt: updatedAt,
            createdAt: createdAt,
            endedAt: endedAt,
            lastActivity: lastActivity,
            focusApp: focusApp,
            tty: tty,
            termSession: termSession,
            termIds: termIds,
            source: source
        )
    }

    static func date(from value: Any?) -> Date? {
        if let ms = value as? Double {
            if ms > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            return Date(timeIntervalSince1970: ms)
        }
        if let ms = value as? Int {
            return date(from: Double(ms))
        }
        return nil
    }
}
