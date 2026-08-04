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

    /// False when no Chat Hub is running: the line is on disk, but nothing will read it until
    /// the Hub starts, so the island must not report the answer as delivered.
    @discardableResult
    func reply(sessionId: String, requestId: String?, text: String) -> Bool {
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
        return activateChatHub()
    }

    /// Ask Chat Hub to create a new session and focus it.
    @discardableResult
    func newSession(provider: String = "claude") -> Bool {
        append([
            "type": "session.new",
            "provider": provider,
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ])
        return activateChatHub()
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
            if name == target || name.contains(target) || (target.contains(name) && !name.isEmpty) {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }
        return false
    }

    /// Focus the *exact* terminal tab/pane hosting an agent session when the terminal
    /// gives us a way in, else just bring the app forward. Every terminal has its own
    /// door: AppleScript for iTerm/Terminal, a control socket for kitty and WezTerm,
    /// a client command for tmux, a workspace path for the editors.
    /// Only ever drives an already-running terminal — never launches a new one.
    ///
    /// Answers the click immediately and finishes the targeted focus in the background:
    /// every door is a subprocess that can take seconds (the first osascript against an app
    /// parks on the macOS Automation consent dialog), and this runs on the main actor, which
    /// also drives the island, the JSONL poll and the permission socket.
    @discardableResult
    func focusTerminal(
        app: String,
        tty: String?,
        session: String?,
        termIds: [String: String]? = nil,
        cwd: String? = nil
    ) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app).first != nil else {
            return activateApp(bundleIdOrName: app)
        }
        Task { [weak self] in
            await self?.driveTerminalDoor(app: app, tty: tty, session: session, termIds: termIds, cwd: cwd)
        }
        // The host terminal is running, so we end up in front of it either way — only the
        // exact tab/pane is still in question, and that answer arrives too late to report.
        return true
    }

    /// The slow half of `focusTerminal`, off the click path.
    private func driveTerminalDoor(
        app: String,
        tty: String?,
        session: String?,
        termIds: [String: String]?,
        cwd: String?
    ) async {
        let ids = termIds ?? [:]

        // Inside tmux the pane is what matters — the host terminal is just the window.
        if let pane = ids["tmuxPane"], !pane.isEmpty {
            await selectTmuxPane(pane: pane, socket: ids["tmuxSocket"])
        }

        switch app {
        case "com.googlecode.iterm2":
            if let session, !session.isEmpty, await runAppleScript(itermScript(sessionId: session)) {
                return
            }
        case "com.apple.Terminal":
            if let tty, !tty.isEmpty, await runAppleScript(terminalScript(tty: tty)) {
                return
            }
        case "net.kovidgoyal.kitty":
            if let window = ids["kittyWindow"], await focusKitty(window: window, socket: ids["kittySocket"]) {
                _ = activateApp(bundleIdOrName: app)
                return
            }
        case "com.github.wez.wezterm":
            if let pane = ids["weztermPane"], await focusWezTerm(pane: pane, socket: ids["weztermSocket"]) {
                _ = activateApp(bundleIdOrName: app)
                return
            }
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed":
            if let cwd, !cwd.isEmpty, await openWorkspace(bundleId: app, path: cwd) {
                return
            }
        default:
            break
        }
        // Ghostty, Warp, Alacritty and friends expose no addressing API — the app itself
        // is the best we can do until we mark tabs via OSC 2 titles.
        _ = activateApp(bundleIdOrName: app)
    }

    // MARK: - Per-terminal doors

    private func focusKitty(window: String, socket: String?) async -> Bool {
        guard let bin = firstExecutable([
            "/Applications/kitty.app/Contents/MacOS/kitten",
            "/opt/homebrew/bin/kitten",
            "/usr/local/bin/kitten",
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty"
        ]) else { return false }
        var args = ["@"]
        if let socket, !socket.isEmpty { args += ["--to", socket] }
        args += ["focus-window", "--match", "id:\(window)"]
        // Needs `allow_remote_control yes` in kitty.conf; a refusal just falls through.
        return await run(bin, args)
    }

    private func focusWezTerm(pane: String, socket: String?) async -> Bool {
        guard let bin = firstExecutable([
            "/Applications/WezTerm.app/Contents/MacOS/wezterm",
            "/opt/homebrew/bin/wezterm",
            "/usr/local/bin/wezterm"
        ]) else { return false }
        var env: [String: String] = [:]
        if let socket, !socket.isEmpty { env["WEZTERM_UNIX_SOCKET"] = socket }
        return await run(bin, ["cli", "activate-pane", "--pane-id", pane], env: env)
    }

    @discardableResult
    private func selectTmuxPane(pane: String, socket: String?) async -> Bool {
        guard let bin = firstExecutable([
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]) else { return false }
        var prefix: [String] = []
        if let socket, !socket.isEmpty { prefix = ["-S", socket] }
        let window = await run(bin, prefix + ["select-window", "-t", pane])
        let selected = await run(bin, prefix + ["select-pane", "-t", pane])
        return window || selected
    }

    private func openWorkspace(bundleId: String, path: String) async -> Bool {
        await run("/usr/bin/open", ["-b", bundleId, path])
    }

    private func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a helper off the main actor and never waits on it forever: a control socket whose
    /// server died (kitty/WezTerm) answers nothing at all, and the first osascript against an app
    /// blocks until the user answers the Automation consent dialog — which for an LSUIElement app
    /// can open behind another window. `timeout` is the point where we stop caring.
    private nonisolated func run(
        _ launchPath: String,
        _ args: [String],
        env: [String: String] = [:],
        timeout: TimeInterval = 5
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let call = ProcessCall(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                if !env.isEmpty {
                    var merged = ProcessInfo.processInfo.environment
                    env.forEach { merged[$0.key] = $0.value }
                    proc.environment = merged
                }
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                proc.terminationHandler = { finished in
                    call.finish(finished.terminationStatus == 0)
                }
                do {
                    try proc.run()
                } catch {
                    call.finish(false)
                    return
                }
                call.arm(proc, timeout: timeout)
            }
        }
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

    /// Long watchdog on purpose: the first run against a terminal sits on the Automation consent
    /// dialog, and killing osascript would take the dialog with it — the user would never get to
    /// grant the permission that makes tab-exact focus work at all.
    private nonisolated func runAppleScript(_ source: String) async -> Bool {
        await run("/usr/bin/osascript", ["-e", source], timeout: 90)
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
                || (name == "Electron" && path.localizedCaseInsensitiveContains("agent-desktop-suite"))
                || path.localizedCaseInsensitiveContains("Chat Hub.app")
            if hit {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }

        // Same id as chat-hub/electron-builder.yml `appId` — the only identity that survives a
        // productName/path change. `urlForApplication` also finds a signed app outside
        // /Applications (for example, a release opened from Downloads), which matters here:
        // the command was already written before we try to launch the Hub.
        let bundleId = "com.agentdesktop.chat-hub"
        if let packaged = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: packaged, configuration: configuration)
            return true
        }

        // Keep the explicit fallback for an app bundle that has not yet been registered by
        // Launch Services (common immediately after a local install).
        let packaged = URL(fileURLWithPath: "/Applications/Chat Hub.app")
        if FileManager.default.fileExists(atPath: packaged.path) {
            NSWorkspace.shared.openApplication(at: packaged, configuration: NSWorkspace.OpenConfiguration())
            return true
        }

        for app in apps where app.localizedName == "Electron" {
            app.activate(options: [.activateAllWindows])
            return true
        }
        return false
    }
}

/// One child process and the continuation waiting on it. Exit and watchdog race each other and
/// only the first may answer — resuming a continuation twice traps.
private final class ProcessCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var process: Process?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    /// Called after a successful launch: a child still alive at `timeout` is waiting on something
    /// that is not coming back, so kill it rather than leak the process for the app's lifetime.
    func arm(_ process: Process, timeout: TimeInterval) {
        lock.lock()
        let pending = continuation != nil
        // A fast helper can exit before we get here; holding it then would keep the
        // process ↔ terminationHandler ↔ self cycle alive with nobody left to break it.
        if pending { self.process = process }
        lock.unlock()
        guard pending else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            self.expire()
        }
    }

    func finish(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        process = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    private func expire() {
        lock.lock()
        let pending = continuation
        continuation = nil
        let victim = process
        process = nil
        lock.unlock()
        guard let pending else { return }
        victim?.terminate()
        pending.resume(returning: false)
    }
}
