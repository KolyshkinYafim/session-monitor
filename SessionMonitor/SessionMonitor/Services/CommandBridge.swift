import AppKit
import Foundation

/// Writes reverse commands for Chat Hub.
@MainActor
final class CommandBridge {
    private let fileURL: URL

    init(fileURL: URL = BridgePath.commandsFile) {
        self.fileURL = fileURL
    }

    @discardableResult
    func focusSession(id: String) -> Bool {
        append([
            "type": "session.focus",
            "id": id,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ])
        return activateChatHub()
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
        _ = activateChatHub()
    }

    /// Bring an already-running app forward (e.g. the terminal hosting a Claude hook session).
    /// Tries bundle id first, then a localized-name match. Returns true if something was activated.
    @discardableResult
    func activateApp(bundleIdOrName: String) -> Bool {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdOrName).first {
            app.activate(options: [.activateAllWindows])
            return true
        }
        let target = bundleIdOrName.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            let name = (app.localizedName ?? "").lowercased()
            if name == target || name.contains(target) || target.contains(name) && !name.isEmpty {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }
        return false
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

    /// Returns true if a Chat Hub / chat-hub Electron process was activated.
    private func activateChatHub() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            let path = (app.executableURL?.path ?? "") + " " + (app.bundleURL?.path ?? "")
            let name = app.localizedName ?? ""
            let hit =
                path.localizedCaseInsensitiveContains("chat-hub")
                || name.localizedCaseInsensitiveContains("Chat Hub")
                || name == "Electron" && path.localizedCaseInsensitiveContains("agent-desktop-suite")
            if hit {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }

        // Bundle id candidates
        for bundleId in ["com.agentdesktop.ChatHub", "com.electron.chat-hub"] {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }

        // Last resort: Electron processes (dev hub)
        for app in apps where app.localizedName == "Electron" {
            app.activate(options: [.activateAllWindows])
            return true
        }
        return false
    }
}
