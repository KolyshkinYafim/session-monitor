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

    /// Focus the *exact* terminal tab/session hosting a Claude hook session when we can
    /// (iTerm by session id, Terminal.app by tty), else just bring the terminal forward.
    /// Only ever drives an already-running terminal — never launches a new one.
    @discardableResult
    func focusTerminal(app: String, tty: String?, session: String?) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app).first != nil else {
            return activateApp(bundleIdOrName: app)
        }
        var script: String?
        if app == "com.googlecode.iterm2", let session, !session.isEmpty {
            script = itermScript(sessionId: session)
        } else if app == "com.apple.Terminal", let tty, !tty.isEmpty {
            script = terminalScript(tty: tty)
        }
        // The scripts `activate` first, so even a no-match still brings the terminal forward.
        // If AppleScript is blocked (Automation permission not yet granted), fall back.
        if let script, runAppleScript(script) {
            return true
        }
        return activateApp(bundleIdOrName: app)
    }

    private func itermScript(sessionId: String) -> String {
        """
        tell application "iTerm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if (id of s) is "\(sessionId)" then
                  select w
                  select t
                  select s
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    }

    private func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              if (tty of t) is "\(tty)" then
                set selected of t to true
                set frontmost of w to true
                return
              end if
            end repeat
          end repeat
        end tell
        """
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
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
