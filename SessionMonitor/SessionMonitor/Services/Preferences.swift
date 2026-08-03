import AppKit
import Observation
import ServiceManagement

/// Persisted settings (UserDefaults) — Vibe-style surface, wired where the app supports it.
@MainActor
@Observable
final class Preferences {
    enum WidthStyle: String, CaseIterable, Identifiable {
        case compact, normal, wide
        var id: String { rawValue }
        var label: String {
            switch self {
            case .compact: "Compact"
            case .normal: "Normal"
            case .wide: "Wide"
            }
        }
        var scale: CGFloat {
            switch self {
            case .compact: 0.9
            case .normal: 1.0
            case .wide: 1.15
            }
        }
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, integrations, notifications, display, sound, usage
        case shortcuts, ssh, labs, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .integrations: "Integrations"
            case .notifications: "Notifications"
            case .display: "Display"
            case .sound: "Sound"
            case .usage: "Usage"
            case .shortcuts: "Shortcuts"
            case .ssh: "SSH Remote"
            case .labs: "Labs"
            case .about: "About"
            }
        }
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .integrations: "puzzlepiece.extension"
            case .notifications: "bell"
            case .display: "textformat.size"
            case .sound: "speaker.wave.2"
            case .usage: "chart.bar"
            case .shortcuts: "keyboard"
            case .ssh: "network"
            case .labs: "flask"
            case .about: "info.circle"
            }
        }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    var hoverExpand: Bool {
        didSet { defaults.set(hoverExpand, forKey: Keys.hoverExpand) }
    }

    var autoExpandOnWaiting: Bool {
        didSet { defaults.set(autoExpandOnWaiting, forKey: Keys.autoExpandWaiting) }
    }

    /// Seconds the list stays open after the pointer leaves. Too short feels twitchy,
    /// too long feels stuck — hence a setting rather than a constant.
    var hoverLeaveDelay: Double {
        didSet { defaults.set(hoverLeaveDelay, forKey: Keys.hoverLeaveDelay) }
    }

    /// Hover list width in points. Long prompts and paths need room — 420 truncated
    /// almost every title.
    var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) }
    }

    /// Tallest the list may get before it scrolls.
    var maxPanelHeight: Double {
        didSet { defaults.set(maxPanelHeight, forKey: Keys.maxPanelHeight) }
    }

    /// Base point size for card text.
    var contentFontSize: Double {
        didSet { defaults.set(contentFontSize, forKey: Keys.contentFontSize) }
    }

    /// Clicking a card focuses its terminal / Hub window. Off = selection only.
    var clickToJump: Bool {
        didSet { defaults.set(clickToJump, forKey: Keys.clickToJump) }
    }

    /// Hide the island entirely while nothing is running.
    var hideWhenEmpty: Bool {
        didSet { defaults.set(hideWhenEmpty, forKey: Keys.hideWhenEmpty) }
    }

    /// Order the panel out while the docking screen shows a fullscreen space — the strip
    /// floats above fullscreen windows, so it is the one thing that breaks them.
    var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Keys.hideInFullscreen) }
    }

    /// Don't auto-expand when the agent's terminal tab is already in focus.
    var smartSuppression: Bool {
        didSet { defaults.set(smartSuppression, forKey: Keys.smartSuppression) }
    }

    /// Seconds a panel opened *by an event* stays open before returning to compact.
    /// Distinct from `hoverLeaveDelay`, which is about the pointer. 0 = stay open.
    var autoRevealDwell: Double {
        didSet { defaults.set(autoRevealDwell, forKey: Keys.autoRevealDwell) }
    }

    /// Hours before a running/waiting session with no signal is retired. 0 = never.
    /// Read by the prune timer; `idleCleanupChoices` is the picker's option list.
    var idleCleanupHours: Int {
        didSet { defaults.set(idleCleanupHours, forKey: Keys.idleCleanupHours) }
    }

    static let idleCleanupChoices = [0, 1, 2, 6, 12, 24]

    static func idleCleanupLabel(_ hours: Int) -> String {
        switch hours {
        case 0: "Off"
        case 1: "1 hour"
        default: "\(hours) hours"
        }
    }

    /// Default provider for “+ New” (Chat Hub).
    var defaultNewProvider: String {
        didSet { defaults.set(defaultNewProvider, forKey: Keys.defaultProvider) }
    }

    // MARK: - Display

    var widthStyle: WidthStyle {
        didSet { defaults.set(widthStyle.rawValue, forKey: Keys.width) }
    }

    /// Collapsed strip preset. Detailed makes the strip wider, so the panel has to be
    /// re-sized when this changes — `IslandGeometry` reads the same value.
    var compactStyle: CompactStyle {
        didSet { defaults.set(compactStyle.rawValue, forKey: Keys.compactStyle) }
    }

    var screenName: String? {
        didSet {
            if let screenName { defaults.set(screenName, forKey: Keys.screen) }
            else { defaults.removeObject(forKey: Keys.screen) }
        }
    }

    /// Extra points added to estimated notch width (can be negative). 0 = API estimate.
    var notchWidthOffset: Double {
        didSet { defaults.set(notchWidthOffset, forKey: Keys.notchWidthOffset) }
    }

    /// Extra points added to strip height (can be negative).
    var notchHeightOffset: Double {
        didSet { defaults.set(notchHeightOffset, forKey: Keys.notchHeightOffset) }
    }

    var showPathsInRows: Bool {
        didSet { defaults.set(showPathsInRows, forKey: Keys.showPaths) }
    }

    var showActivityDetail: Bool {
        didSet { defaults.set(showActivityDetail, forKey: Keys.showActivityDetail) }
    }

    var showStatusChips: Bool {
        didSet { defaults.set(showStatusChips, forKey: Keys.showStatusChips) }
    }

    // MARK: - Notifications

    var notifyWaiting: Bool {
        didSet { defaults.set(notifyWaiting, forKey: Keys.notifyWaiting) }
    }

    var notifyDone: Bool {
        didSet { defaults.set(notifyDone, forKey: Keys.notifyDone) }
    }

    var notifyError: Bool {
        didSet { defaults.set(notifyError, forKey: Keys.notifyError) }
    }

    /// A finished turn peeks the list open instead of only glowing. Off by default —
    /// today's behaviour reveals on waiting alone, and completions are far more frequent.
    var expandForCompletion: Bool {
        didSet { defaults.set(expandForCompletion, forKey: Keys.expandForCompletion) }
    }

    // MARK: - Sound

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }

    var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) }
    }

    // MARK: - Labs

    var experimentalToolCards: Bool {
        didSet { defaults.set(experimentalToolCards, forKey: Keys.labToolCards) }
    }

    var experimentalSSH: Bool {
        didSet { defaults.set(experimentalSSH, forKey: Keys.labSSH) }
    }

    // MARK: -

    private let defaults: UserDefaults
    private enum Keys {
        static let width = "island.widthStyle"
        static let screen = "island.screenName"
        static let launchAtLogin = "general.launchAtLogin"
        static let hoverExpand = "general.hoverExpand"
        static let autoExpandWaiting = "general.autoExpandWaiting"
        static let hoverLeaveDelay = "general.hoverLeaveDelay"
        static let clickToJump = "general.clickToJump"
        static let panelWidth = "display.panelWidth"
        static let maxPanelHeight = "display.maxPanelHeight"
        static let contentFontSize = "display.contentFontSize"
        static let hideWhenEmpty = "general.hideWhenEmpty"
        static let hideInFullscreen = "general.hideInFullscreen"
        static let smartSuppression = "general.smartSuppression"
        static let autoRevealDwell = "general.autoRevealDwell"
        static let idleCleanupHours = "general.idleCleanupHours"
        static let compactStyle = "display.compactStyle"
        static let defaultProvider = "general.defaultNewProvider"
        static let notchWidthOffset = "display.notchWidthOffset"
        static let notchHeightOffset = "display.notchHeightOffset"
        static let showPaths = "display.showPaths"
        static let showActivityDetail = "display.showActivityDetail"
        static let showStatusChips = "display.showStatusChips"
        static let notifyWaiting = "notify.waiting"
        static let notifyDone = "notify.done"
        static let notifyError = "notify.error"
        static let expandForCompletion = "notify.expandForCompletion"
        static let soundsEnabled = "soundsEnabled"
        static let soundVolume = "sound.volume"
        static let labToolCards = "labs.toolCards"
        static let labSSH = "labs.ssh"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.width) ?? WidthStyle.normal.rawValue
        widthStyle = WidthStyle(rawValue: raw) ?? .normal
        let styleRaw = defaults.string(forKey: Keys.compactStyle) ?? CompactStyle.clean.rawValue
        compactStyle = CompactStyle(rawValue: styleRaw) ?? .clean
        screenName = defaults.string(forKey: Keys.screen)

        // The registration is the truth — a stored `true` means nothing if the login item
        // was removed in System Settings. `.notFound` also covers unsigned dev runs, where
        // SMAppService can't report anything, so there we fall back to the stored value.
        let loginItem = SMAppService.mainApp.status
        launchAtLogin = loginItem == .notFound
            ? (defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false)
            : loginItem == .enabled
        hoverExpand = defaults.object(forKey: Keys.hoverExpand) as? Bool ?? true
        autoExpandOnWaiting = defaults.object(forKey: Keys.autoExpandWaiting) as? Bool ?? true
        // 0.12s collapsed the list out from under the pointer before a click landed.
        hoverLeaveDelay = defaults.object(forKey: Keys.hoverLeaveDelay) as? Double ?? 0.6
        panelWidth = defaults.object(forKey: Keys.panelWidth) as? Double ?? 560
        maxPanelHeight = defaults.object(forKey: Keys.maxPanelHeight) as? Double ?? 460
        contentFontSize = defaults.object(forKey: Keys.contentFontSize) as? Double ?? 12.5
        clickToJump = defaults.object(forKey: Keys.clickToJump) as? Bool ?? true
        hideWhenEmpty = defaults.object(forKey: Keys.hideWhenEmpty) as? Bool ?? false
        hideInFullscreen = defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? false
        smartSuppression = defaults.object(forKey: Keys.smartSuppression) as? Bool ?? true
        autoRevealDwell = defaults.object(forKey: Keys.autoRevealDwell) as? Double ?? 5
        idleCleanupHours = defaults.object(forKey: Keys.idleCleanupHours) as? Int ?? 6
        defaultNewProvider = defaults.string(forKey: Keys.defaultProvider) ?? "claude"

        notchWidthOffset = defaults.object(forKey: Keys.notchWidthOffset) as? Double ?? 0
        notchHeightOffset = defaults.object(forKey: Keys.notchHeightOffset) as? Double ?? 0
        showPathsInRows = defaults.object(forKey: Keys.showPaths) as? Bool ?? true
        showActivityDetail = defaults.object(forKey: Keys.showActivityDetail) as? Bool ?? true
        showStatusChips = defaults.object(forKey: Keys.showStatusChips) as? Bool ?? true

        notifyWaiting = defaults.object(forKey: Keys.notifyWaiting) as? Bool ?? true
        notifyDone = defaults.object(forKey: Keys.notifyDone) as? Bool ?? true
        notifyError = defaults.object(forKey: Keys.notifyError) as? Bool ?? true
        expandForCompletion = defaults.bool(forKey: Keys.expandForCompletion)

        // IslandSounds also reads this key.
        if defaults.object(forKey: Keys.soundsEnabled) == nil {
            soundsEnabled = true
        } else {
            soundsEnabled = defaults.bool(forKey: Keys.soundsEnabled)
        }
        soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.55

        experimentalToolCards = defaults.bool(forKey: Keys.labToolCards)
        experimentalSSH = defaults.bool(forKey: Keys.labSSH)

        // `didSet` never fires from init, so a stored `true` with no registration yet — a
        // fresh install to /Applications, where install-app.sh seeded the key — would show
        // the toggle on and start nothing. Reconcile once, here.
        if launchAtLogin, SMAppService.mainApp.status != .enabled {
            applyLaunchAtLogin()
        }
    }

    /// The toggle has to move the actual login item, or turning it off changes nothing.
    /// This registration is the only autostart mechanism — packaging/install-app.sh removes
    /// the LaunchAgent older installs left behind rather than competing with it.
    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("SessionMonitor: launch at login \(launchAtLogin ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
    }
}
