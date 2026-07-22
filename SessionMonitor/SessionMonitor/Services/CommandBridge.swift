import AppKit
import Foundation

/// Writes reverse commands for Chat Hub (and local mock handling).
@MainActor
final class CommandBridge {
    private let fileURL: URL

    init(fileURL: URL = BridgePath.commandsFile) {
        self.fileURL = fileURL
    }

    func focusSession(id: String) {
        append([
            "type": "session.focus",
            "id": id,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ])
        activateChatHub()
    }

    func reply(sessionId: String, requestId: String?, text: String) {
        var payload: [String: Any] = [
            "type": "session.reply",
            "id": sessionId,
            "text": text,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let requestId {
            payload["requestId"] = requestId
        }
        append(payload)
        activateChatHub()
    }

    private func append(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line.append("\n")
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private func activateChatHub() {
        let candidates = [
            "com.agentdesktop.ChatHub",
            "com.electron.chat-hub",
            "chat-hub"
        ]
        for bundleId in candidates {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                return
            }
        }

        // Best-effort: open any running Electron named Chat Hub via AppleScript.
        let script = """
        tell application "System Events"
          set procs to name of every process whose background only is false
          repeat with p in procs
            if p contains "Chat Hub" or p contains "chat-hub" or p contains "Electron" then
              try
                set frontmost of process p to true
                return
              end try
            end if
          end repeat
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
}
