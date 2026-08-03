import AppKit
import Darwin

/// Whoever holds this lock owns `monitor.sock`. A second copy (a Debug build launched
/// over the installed one, say) would otherwise unlink the live socket and leave every
/// hook talking to a listener nobody is watching.
enum SingleInstance {
    /// Held for the process lifetime; only ever touched during launch.
    nonisolated(unsafe) private static var lockFD: Int32 = -1

    static func acquire() -> Bool {
        let url = BridgePath.eventsFile
            .deletingLastPathComponent()
            .appendingPathComponent("monitor.lock")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }  // can't lock → don't block the user
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }
}

/// Which tree this binary came from. The version keys never move between builds, so the only
/// way to tell whether the island running from /Applications is the code in front of you is the
/// revision packaging/stamp-build-identity.sh writes into Info.plist at build time.
enum BuildInfo {
    static var version: String { infoString("CFBundleShortVersionString") ?? "0.0.0" }
    static var build: String { infoString("CFBundleVersion") ?? "0" }
    static var revision: String { identity["SMBuildRevision"] ?? "unknown" }
    static var builtAt: String { identity["SMBuildDate"] ?? "unknown" }

    /// One line for the About page: "0.1.0 (137) · 6b9208b-dirty · 2026-08-01T14:03:11Z".
    static var summary: String { "\(version) (\(build)) · \(revision) · \(builtAt)" }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Its own resource, not Info.plist: the stamping build phase runs before Xcode copies
    /// Info.plist into the bundle, so keys written there never reach the shipped app.
    private static let identity: [String: String] = {
        guard let url = Bundle.main.url(forResource: "BuildIdentity", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: String]
        else { return [:] }
        return dict
    }()
}

@MainActor
final class AppController {
    let store = SessionStore()
    private let prefs = Preferences()
    private let notifications = NotificationService()
    private var mock: MockProducer?
    private var bridge: ChatHubBridge?
    private var socketServer: MonitorSocketServer?
    private var statusItem: StatusItemController?
    private var panel: IslandPanelController?
    private var settings: SettingsWindowController?
    private let hotKey = HotKeyManager()
    private var pruneTimer: Timer?

    func start() {
        notifications.requestAuthorization()

        let panel = IslandPanelController(
            store: store,
            prefs: prefs,
            bridgePath: BridgePath.displayPath,
            onQuit: { NSApp.terminate(nil) }
        )
        self.panel = panel

        let socket = MonitorSocketServer(store: store)
        store.socketServer = socket
        socket.start()
        self.socketServer = socket

        settings = SettingsWindowController(
            prefs: prefs,
            onApplyDisplay: { [weak self] in
                self?.panel?.applyPreferences()
            },
            onQuit: { NSApp.terminate(nil) }
        )

        store.setStatusChangeHandler { [weak self] session, status, previous in
            if !session.isMock {
                self?.notifications.notifyIfNeeded(session: session, status: status, previous: previous)
                IslandSounds.playTransition(from: previous, to: status)
            }
            self?.statusItem?.updateBadge()
            if status == .waitingInput, !session.isMock {
                self?.panel?.pulseForWaiting()
            } else {
                self?.panel?.refreshCompactSchedule()
                // After the compact schedule, never before: it would close the reveal the
                // completion just opened.
                if !session.isMock, previous == .running, status == .idle || status == .done {
                    self?.panel?.presentForCompletion()
                }
            }
        }

        panel.start()
        let status = StatusItemController(store: store, panel: panel, prefs: prefs)
        status.onOpenSettings = { [weak self] in
            self?.settings?.show()
        }
        self.statusItem = status

        NotificationCenter.default.addObserver(
            forName: .sessionMonitorOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settings?.show() }
        }

        let mockEnabled =
            ProcessInfo.processInfo.environment["SESSION_MONITOR_MOCK"] == "1"
        if mockEnabled {
            let mock = MockProducer(store: store)
            mock.start()
            self.mock = mock
        }

        let bridge = ChatHubBridge(store: store)
        bridge.start()
        self.bridge = bridge

        // Replay can resurrect sessions whose process died long ago — retire them now,
        // then keep checking so a killed agent stops holding a live dot forever.
        store.pruneStaleSessions(idleCleanupHours: prefs.idleCleanupHours)
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.pruneStaleSessions(idleCleanupHours: self.prefs.idleCleanupHours)
                self.statusItem?.updateBadge()
            }
        }

        hotKey.register { [weak self] in
            self?.panel?.toggleExpanded()
        }
    }

    func stop() {
        hotKey.unregister()
        pruneTimer?.invalidate()
        pruneTimer = nil
        mock?.stop()
        bridge?.stop()
        socketServer?.stop()
        panel?.stop()
    }
}
