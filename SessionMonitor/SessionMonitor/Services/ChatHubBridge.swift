import Foundation

@MainActor
final class ChatHubBridge {
    private let store: SessionStore
    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
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
        replaying = true
        drain()
        replaying = false
        startWatching()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drain()
            }
        }
    }

    func stop() {
        started = false
        pollTimer?.invalidate()
        pollTimer = nil
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
                self?.drain()
            }
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()
    }

    private func drain() {
        guard started else { return }
        ensureFile()
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

    private func flushLines() {
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            if let event = parseLine(line) {
                store.apply(normalizeReplay(event))
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

    private func parseLine(_ line: String) -> SessionEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "session.upsert":
            guard let sessionObj = obj["session"] as? [String: Any],
                  let meta = parseSession(sessionObj)
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

    private func parseSession(_ obj: [String: Any]) -> SessionMeta? {
        guard let id = obj["id"] as? String,
              let title = obj["title"] as? String,
              let provider = obj["provider"] as? String,
              let statusRaw = obj["status"] as? String,
              let status = SessionStatus(rawValue: statusRaw)
        else { return nil }

        let cwd = obj["cwd"] as? String
        let focusApp = obj["focusApp"] as? String
        let updatedAt = date(from: obj["updatedAt"]) ?? Date()
        let createdAt = date(from: obj["createdAt"]) ?? updatedAt
        return SessionMeta(
            id: id,
            title: title,
            provider: provider,
            cwd: cwd,
            status: status,
            updatedAt: updatedAt,
            createdAt: createdAt,
            focusApp: focusApp
        )
    }

    private func date(from value: Any?) -> Date? {
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
