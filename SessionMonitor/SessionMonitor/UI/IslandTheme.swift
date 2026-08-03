import SwiftUI

/// Vibe-like proportions: wide enough for rows, compact height, count on the right wing.
enum IslandTheme {
    static let waiting = Color(hex: 0xFF9F0A)
    static let running = Color(hex: 0x30D158)
    static let error = Color(hex: 0xFF453A)
    static let idle = Color.white.opacity(0.28)
    static let shellFill = Color.black

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 12.5, weight: .semibold)
    static let metaFont = Font.system(size: 10.5)
    static let chipFont = Font.system(size: 9, weight: .bold)
    static let countFont = Font.system(size: 14, weight: .bold, design: .rounded)
    static let miniTitleFont = Font.system(size: 12.5, weight: .semibold)
    static let miniMetaFont = Font.system(size: 10.5, weight: .medium)

    /// Hardware notch empty zone (keep wider than camera so wing content never sits under it).
    static let defaultNotchWidth: CGFloat = 190
    static let minNotchWidth: CGFloat = 170
    static let maxNotchWidth: CGFloat = 220

    /// Compact strip wings (left icons / right count) — outside the camera.
    static let wingWidth: CGFloat = 64
    /// Detailed strip wings: enough for a truncated session title on the left and a status
    /// word plus count on the right, still one wing per side of the camera housing.
    static let detailedWingWidth: CGFloat = 168
    /// Screen edge the strip never crosses — menu bar extras live on the right end.
    static let stripEdgeMargin: CGFloat = 24
    /// Compact total height ≈ menu bar (no fat empty body).
    static let stripHang: CGFloat = 2
    static let stripBottomRadius: CGFloat = 16
    /// Detailed strip text: menu-bar sized, so the title reads as part of the bar rather
    /// than as a floating card.
    static let stripTitleFont = Font.system(size: 11.5, weight: .semibold)
    static let stripStatusFont = Font.system(size: 10, weight: .semibold)

    /// Hover list (activity) — wider, Vibe-like cards.
    static let activityWidth: CGFloat = 420
    static let rowHeight: CGFloat = 64
    /// The optional folder-path line adds a third line to every card.
    static let rowPathExtra: CGFloat = 15
    /// Header row inside the hover list (count + settings gear).
    static let toolbarHeight: CGFloat = 32
    static let rowCorner: CGFloat = 14
    static let avatarSize: CGFloat = 28
    static let statusDot: CGFloat = 7
    /// Cap on cards drawn in the hover list — the panel height decides the real limit.
    static let miniRowCount: Int = 8
    static let listPad: CGFloat = 10
    static let newButtonHeight: CGFloat = 40
    /// Inline Allow/Deny row under a waiting card.
    static let actionRowHeight: CGFloat = 38
    static let panelCorner: CGFloat = 22

    static let expandedWidth: CGFloat = 420
    static let boardMinHeight: CGFloat = 340

    /// Fallback only — the real value is `Preferences.hoverLeaveDelay`.
    static let idleCompactDelay: TimeInterval = 0.6
    static let morphDuration: CFTimeInterval = 0.28

    static func providerColor(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "claude": Color(hex: 0xFF9F0A)
        case "grok": Color(hex: 0x64D2FF)
        case "codex": Color(hex: 0x30D158)
        case "opencode": Color(hex: 0xBF5AF2)
        case "gemini": Color(hex: 0x5AC8FA)
        default: Color.white.opacity(0.55)
        }
    }

    static func providerLetter(_ provider: String) -> String {
        guard let c = provider.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(c).uppercased()
    }

    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .waitingInput: waiting
        case .running: running
        case .error: error
        case .idle, .done: idle
        }
    }

    static func statusChipForeground(_ status: SessionStatus) -> Color {
        switch status {
        case .waitingInput: waiting
        case .running: running
        case .error: error
        case .idle, .done: Color.white.opacity(0.45)
        }
    }

    static func statusChipBackground(_ status: SessionStatus) -> Color {
        switch status {
        case .waitingInput: waiting.opacity(0.16)
        case .running: running.opacity(0.16)
        case .error: error.opacity(0.16)
        case .idle, .done: Color.white.opacity(0.06)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
