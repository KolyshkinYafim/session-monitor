import AppKit

/// Per-event cues for island state changes. Vibe ships downloadable packs; we map each event
/// to a named macOS system sound (or Off) so the app stays a single binary with nothing to bundle.
@MainActor
enum IslandSounds {
    /// The events a user can put a sound on. Every case is reachable from a real transition —
    /// Vibe's "Context Limit" and "Spam Detection" rows are missing here because no producer
    /// sends us those signals yet, and a picker that can never fire is worse than no picker.
    enum Event: String, CaseIterable, Identifiable {
        case sessionStart
        case taskComplete
        case taskError
        case approvalNeeded
        case taskAcknowledge
        case idleReminder

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sessionStart: "Session Start"
            case .taskComplete: "Task Complete"
            case .taskError: "Task Error"
            case .approvalNeeded: "Approval Needed"
            case .taskAcknowledge: "Task Acknowledge"
            case .idleReminder: "Idle Reminder"
            }
        }

        /// Vibe's own subtitles, kept verbatim for parity.
        var subtitle: String {
            switch self {
            case .sessionStart: "New Claude / Codex / Gemini session"
            case .taskComplete: "AI finished its turn"
            case .taskError: "Tool failure or API error"
            case .approvalNeeded: "Permission or question pending"
            case .taskAcknowledge: "You submitted a prompt"
            case .idleReminder: "AI is waiting for your input"
            }
        }

        /// What the hardcoded map played before this picker existed, so an install that never
        /// opens Settings sounds exactly the same after the upgrade.
        var defaultSound: String {
            switch self {
            case .sessionStart: "Pop"
            case .taskComplete: "Glass"
            case .taskError: "Basso"
            case .approvalNeeded: "Tink"
            case .taskAcknowledge: off
            case .idleReminder: off
            }
        }

        var defaultsKey: String { "sound.\(rawValue)" }

        /// Which group the Settings page files this row under (Vibe's own grouping).
        var group: Group {
            switch self {
            case .sessionStart, .taskComplete, .taskError: .session
            case .approvalNeeded, .taskAcknowledge: .interactions
            case .idleReminder: .system
            }
        }

        enum Group: String, CaseIterable, Identifiable {
            case session, interactions, system
            var id: String { rawValue }
            var title: String {
                switch self {
                case .session: "Session"
                case .interactions: "Interactions"
                case .system: "System"
                }
            }
        }
    }

    /// Stored in place of a sound name when a row is Off. Nonisolated because the nested
    /// `Event` enum is not main-actor bound and its `defaultSound` needs this sentinel.
    nonisolated static let off = "off"

    /// Whatever `NSSound(named:)` can resolve on this machine — enumerating beats a hardcoded
    /// list, which would drift the first time Apple retires a chime.
    static let availableSounds: [String] = {
        let dirs = [
            "/System/Library/Sounds",
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds"),
        ]
        var names = Set<String>()
        for dir in dirs {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            where !file.hasPrefix(".") {
                names.insert((file as NSString).deletingPathExtension)
            }
        }
        return names.sorted()
    }()

    static func sound(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.defaultsKey) ?? event.defaultSound
    }

    static func setSound(_ name: String, for event: Event) {
        UserDefaults.standard.set(name, forKey: event.defaultsKey)
    }

    static func play(_ event: Event) {
        guard enabled, !isQuietHour else { return }
        emit(sound(for: event))
    }

    /// The ▶ button has to be audible even with the master switch off or inside Quiet Hours —
    /// it is how you audition a sound, not a notification.
    static func preview(_ event: Event) {
        emit(sound(for: event))
    }

    /// Pick a sound from a status transition (real sessions only).
    static func playTransition(from previous: SessionStatus?, to status: SessionStatus) {
        guard previous != status else { return }
        switch status {
        case .running:
            // Answering a prompt moves waiting → running: that is the acknowledge cue, not a
            // new session starting.
            if previous == .waitingInput {
                play(.taskAcknowledge)
            } else if previous == nil || previous == .idle || previous == .done {
                play(.sessionStart)
            }
        case .waitingInput:
            play(.approvalNeeded)
        case .done:
            play(.taskComplete)
        case .error:
            play(.taskError)
        case .idle:
            // running → idle is "agent finished its turn", the moment you want to hear.
            if previous == .running || previous == .waitingInput { play(.taskComplete) }
        }
    }

    // MARK: - Quiet Hours

    enum QuietHours {
        static let enabledKey = "sound.quietHoursEnabled"
        /// Minutes since midnight — a wall-clock time survives timezone changes, a Date does not.
        static let fromKey = "sound.quietFrom"
        static let toKey = "sound.quietTo"
        static let defaultFrom = 22 * 60
        static let defaultTo = 8 * 60
    }

    static var isQuietHour: Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: QuietHours.enabledKey) else { return false }
        let from = d.object(forKey: QuietHours.fromKey) as? Int ?? QuietHours.defaultFrom
        let to = d.object(forKey: QuietHours.toKey) as? Int ?? QuietHours.defaultTo
        guard from != to else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A range that ends before it starts wraps past midnight — 22:00 → 08:00 is the default.
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }

    // MARK: -

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    private static var volume: Float {
        let v = UserDefaults.standard.object(forKey: "sound.volume") as? Double ?? 0.55
        return Float(min(max(v, 0), 1))
    }

    /// Silently does nothing for `off` and for a name the system no longer ships — a beep in
    /// place of a retired chime would be louder than what the user chose.
    private static func emit(_ name: String) {
        guard name != off, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = volume
        sound.play()
    }
}

/// Settings needs bindings; the play path stays static because it runs from the store callback
/// where there is no view model to reach.
@MainActor
@Observable
final class SoundSettingsModel {
    private(set) var choices: [IslandSounds.Event: String]

    var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: IslandSounds.QuietHours.enabledKey) }
    }

    var quietFromMinutes: Int {
        didSet { defaults.set(quietFromMinutes, forKey: IslandSounds.QuietHours.fromKey) }
    }

    var quietToMinutes: Int {
        didSet { defaults.set(quietToMinutes, forKey: IslandSounds.QuietHours.toKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choices = Dictionary(
            uniqueKeysWithValues: IslandSounds.Event.allCases.map { ($0, IslandSounds.sound(for: $0)) }
        )
        quietHoursEnabled = defaults.bool(forKey: IslandSounds.QuietHours.enabledKey)
        quietFromMinutes = defaults.object(forKey: IslandSounds.QuietHours.fromKey) as? Int
            ?? IslandSounds.QuietHours.defaultFrom
        quietToMinutes = defaults.object(forKey: IslandSounds.QuietHours.toKey) as? Int
            ?? IslandSounds.QuietHours.defaultTo
    }

    subscript(event: IslandSounds.Event) -> String {
        get { choices[event] ?? event.defaultSound }
        set {
            choices[event] = newValue
            IslandSounds.setSound(newValue, for: event)
        }
    }

    /// A stored name the system no longer ships would otherwise select nothing in the picker.
    func options(for event: IslandSounds.Event) -> [String] {
        let current = self[event]
        guard current != IslandSounds.off, !IslandSounds.availableSounds.contains(current) else {
            return IslandSounds.availableSounds
        }
        return ([current] + IslandSounds.availableSounds).sorted()
    }
}
