import AppKit
import Observation

/// Persisted island preferences (UserDefaults). Width style + which display it docks to.
@MainActor
@Observable
final class Preferences {
    enum WidthStyle: String, CaseIterable, Identifiable {
        case compact, normal, wide
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// Multiplier applied to the base pill/expanded widths.
        var scale: CGFloat {
            switch self {
            case .compact: 0.86
            case .normal: 1.0
            case .wide: 1.2
            }
        }
    }

    var widthStyle: WidthStyle {
        didSet { defaults.set(widthStyle.rawValue, forKey: Keys.width) }
    }

    /// `localizedName` of the preferred display, or `nil` for automatic (primary display).
    var screenName: String? {
        didSet {
            if let screenName { defaults.set(screenName, forKey: Keys.screen) }
            else { defaults.removeObject(forKey: Keys.screen) }
        }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let width = "island.widthStyle"
        static let screen = "island.screenName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.width) ?? WidthStyle.normal.rawValue
        widthStyle = WidthStyle(rawValue: raw) ?? .normal
        screenName = defaults.string(forKey: Keys.screen)
    }
}
