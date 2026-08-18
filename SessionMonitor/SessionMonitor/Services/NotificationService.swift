import AppKit
import CoreGraphics
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// Repeating "still waiting" timers, keyed by session id.
    private var reminders: [String: Timer] = [:]

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyIfNeeded(session: SessionMeta, status: SessionStatus, previous: SessionStatus?) {
        guard previous != status else { return }
        // Any transition ends the wait the reminder was scheduled for — including the one that
        // starts a new wait, which schedules a fresh timer below.
        cancelReminder(for: session.id)

        let d = UserDefaults.standard
        switch status {
        case .waitingInput:
            guard d.object(forKey: "notify.waiting") as? Bool ?? true else { return }
            scheduleReminder(for: session)
        case .done:
            guard d.object(forKey: "notify.done") as? Bool ?? true else { return }
        case .error:
            guard d.object(forKey: "notify.error") as? Bool ?? true else { return }
        case .idle:
            // Turn finished (Stop hook). Not a "waiting" badge, but still worth a banner.
            guard previous == .running || previous == .waitingInput else { return }
            guard d.object(forKey: "notify.done") as? Bool ?? true else { return }
        default:
            return
        }

        // After the reminder is armed: a scene you cannot see should silence the banner, not
        // cancel the wait itself.
        guard !QuietScenes.isActive else { return }

        deliver(
            title: "\(statusTitle(status, previous: previous)) · \(session.provider)",
            subtitle: session.projectLabel,
            body: session.lastActivity ?? session.title,
            identifier: "\(session.id)-\(status.rawValue)-\(UUID().uuidString)"
        )
    }

    // MARK: - Follow-up reminder

    /// Vibe's "remind me again": a session that is still waiting N minutes later gets another
    /// nudge. A repeating in-process timer rather than a UN trigger, so the reminder can be
    /// cancelled the instant the session moves on.
    private func scheduleReminder(for session: SessionMeta) {
        let minutes = NotificationSettingsModel.followUpMinutesValue
        guard minutes > 0 else { return }
        let id = session.id
        let timer = Timer.scheduledTimer(
            withTimeInterval: Double(minutes) * 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.fireReminder(for: session) }
        }
        reminders[id] = timer
    }

    private func fireReminder(for session: SessionMeta) {
        guard reminders[session.id] != nil else { return }
        IslandSounds.play(.idleReminder)
        guard !QuietScenes.isActive else { return }
        deliver(
            title: "Still waiting · \(session.provider)",
            subtitle: session.projectLabel,
            body: session.pending?.promptText ?? session.lastActivity ?? session.title,
            identifier: "\(session.id)-followup-\(UUID().uuidString)"
        )
    }

    private func cancelReminder(for id: String) {
        reminders.removeValue(forKey: id)?.invalidate()
    }

    // MARK: - Delivery

    private func deliver(title: String, subtitle: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func statusTitle(_ status: SessionStatus, previous: SessionStatus?) -> String {
        switch status {
        case .waitingInput: "Needs input"
        case .done: "Session closed"
        case .error: "Error"
        case .idle: previous == nil ? "Ready" : "Done — your turn"
        default: status.label
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Moments where a banner is either invisible or embarrassing: nobody is at the screen, or the
/// screen is on someone else's display.
@MainActor
enum QuietScenes {
    enum Keys {
        static let focus = "notify.quietFocus"
        static let locked = "notify.quietScreenLocked"
        static let sharing = "notify.quietScreenSharing"
    }

    static var isActive: Bool {
        let d = UserDefaults.standard
        if (d.object(forKey: Keys.focus) as? Bool ?? true), isFocusOn { return true }
        if (d.object(forKey: Keys.locked) as? Bool ?? true), isScreenLockedOrAsleep { return true }
        if (d.object(forKey: Keys.sharing) as? Bool ?? true), isScreenCaptured { return true }
        return false
    }

    /// The Focus state has no public API; the system's own assertion store is the only readable
    /// source, and it sits behind Full Disk Access. Unreadable means "no Focus" so the app never
    /// goes silently mute — Settings shows the grant hint instead.
    static var isFocusOn: Bool {
        guard let data = try? Data(contentsOf: focusAssertionsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else { return false }
        return entries.contains { ($0["storeAssertionRecords"] as? [[String: Any]])?.isEmpty == false }
    }

    /// Settings asks this to explain why the Focus row cannot work yet.
    static var canReadFocusState: Bool {
        FileManager.default.isReadableFile(atPath: focusAssertionsFile.path)
    }

    private static var focusAssertionsFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    private static var isScreenLockedOrAsleep: Bool {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return true }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Int == 1
    }

    /// macOS exposes no query for the recording indicator, so watch for the processes that only
    /// exist while a capture or a sharing session is actually up. Conferencing apps are
    /// deliberately absent: having Zoom open is not the same as sharing a screen.
    private static let capturingBundleIds: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.ScreenSharing",
        "com.obsproject.obs-studio",
    ]

    private static var isScreenCaptured: Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return capturingBundleIds.contains(id)
        }
    }
}

/// Bindings for the Notifications page. The delivery path reads UserDefaults directly because it
/// runs from the store callback, where there is no view model to reach.
@MainActor
@Observable
final class NotificationSettingsModel {
    static let followUpKey = "notify.followUpMinutes"
    /// Off by default: a repeating nudge is opt-in.
    static let followUpChoices = [0, 1, 2, 5, 10, 15, 30]

    static var followUpMinutesValue: Int {
        UserDefaults.standard.object(forKey: followUpKey) as? Int ?? 0
    }

    var quietFocus: Bool {
        didSet { defaults.set(quietFocus, forKey: QuietScenes.Keys.focus) }
    }

    var quietScreenLocked: Bool {
        didSet { defaults.set(quietScreenLocked, forKey: QuietScenes.Keys.locked) }
    }

    var quietScreenSharing: Bool {
        didSet { defaults.set(quietScreenSharing, forKey: QuietScenes.Keys.sharing) }
    }

    /// 0 = Off.
    var followUpMinutes: Int {
        didSet { defaults.set(followUpMinutes, forKey: Self.followUpKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quietFocus = defaults.object(forKey: QuietScenes.Keys.focus) as? Bool ?? true
        quietScreenLocked = defaults.object(forKey: QuietScenes.Keys.locked) as? Bool ?? true
        quietScreenSharing = defaults.object(forKey: QuietScenes.Keys.sharing) as? Bool ?? true
        followUpMinutes = defaults.object(forKey: Self.followUpKey) as? Int ?? 0
    }
}
