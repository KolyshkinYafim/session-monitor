import AppKit

/// Named presets for the collapsed strip (Vibe "Notch style"). Detailed writes the active
/// session's title and status into the wings, so it needs real width beside the camera
/// housing — `IslandGeometry.compactWidth` sizes both from this one value.
enum CompactStyle: String, CaseIterable, Identifiable, Sendable {
    case clean, detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: "Clean"
        case .detailed: "Detailed"
        }
    }

    var subtitle: String {
        switch self {
        case .clean: "More space for menu bar"
        case .detailed: "Session titles & status at a glance"
        }
    }
}

enum IslandGeometry {
    struct Metrics: Equatable {
        var menuBarHeight: CGFloat
        var notchWidth: CGFloat
        var hasNotch: Bool
        var heightOffset: CGFloat = 0
        /// Width of the docking display, so the strip can clamp itself to the menu bar it
        /// lives in. 0 = unknown (view-side fallback before the controller publishes).
        var screenWidth: CGFloat = 0

        var stripHeight: CGFloat {
            max(menuBarHeight + heightOffset, 28) + IslandTheme.stripHang
        }

        /// How wide the strip may grow before it runs into the screen edges. Menu bar
        /// extras own the right end, so we leave a margin instead of claiming everything.
        var usableStripWidth: CGFloat {
            guard screenWidth > 0 else { return 0 }
            return max(screenWidth - IslandTheme.stripEdgeMargin * 2, notchWidth)
        }
    }

    static func metrics(
        for screen: NSScreen,
        notchWidthOffset: CGFloat = 0,
        notchHeightOffset: CGFloat = 0
    ) -> Metrics {
        let full = screen.frame
        let visible = screen.visibleFrame
        let menuH = max(full.maxY - visible.maxY, 24)
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 0 || menuH >= 32
        let baseW = estimatedNotchWidth(screenWidth: full.width, hasNotch: hasNotch)
        // The floor exists to keep wing content clear of the camera housing — a screen
        // without one must be allowed to close the gap completely.
        let minWidth: CGFloat = hasNotch ? 120 : 0
        return Metrics(
            menuBarHeight: max(menuH, safeTop > 0 ? safeTop : menuH),
            notchWidth: max(minWidth, baseW + notchWidthOffset),
            hasNotch: hasNotch,
            heightOffset: notchHeightOffset,
            screenWidth: full.width
        )
    }

    static func estimatedNotchWidth(screenWidth: CGFloat, hasNotch: Bool) -> CGFloat {
        // No camera housing: the strip only needs breathing room between dots and count,
        // not a 150pt hole the notch offset slider could never close.
        guard hasNotch else { return 16 }
        return min(max(screenWidth * 0.103, IslandTheme.minNotchWidth), IslandTheme.maxNotchWidth).rounded()
    }

    static func dockingScreen(preferredName: String?) -> NSScreen? {
        let screens = NSScreen.screens
        if let preferredName, let m = screens.first(where: { $0.localizedName == preferredName }) {
            return m
        }
        if let n = screens.first(where: { $0.safeAreaInsets.top > 0 }) { return n }
        return screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? screens.first
    }

    static func topCenterFrame(size: CGSize, on screen: NSScreen) -> NSRect {
        let full = screen.frame
        let x = (full.midX - size.width / 2).rounded()
        return NSRect(x: x, y: full.maxY - size.height, width: size.width, height: size.height)
    }

    /// A fullscreen space hands the whole display to one window and the menu bar strip
    /// drops out of `visibleFrame`. Asking the window server who owns the frontmost window
    /// would need screen-recording consent, which a menu-bar utility should never prompt for.
    static func isFullscreenSpace(_ screen: NSScreen) -> Bool {
        screen.visibleFrame.height >= screen.frame.height - 1
    }

    static var panelLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
    }

    static func compactWidth(metrics: Metrics, scale: CGFloat, style: CompactStyle = .clean) -> CGFloat {
        let base = style == .detailed ? IslandTheme.detailedWingWidth : IslandTheme.wingWidth
        let full = metrics.notchWidth + base * 2 * scale
        // Detailed wings on a 13" display would run under the clock and off both edges,
        // so the menu bar budget wins over the requested width.
        let budget = metrics.usableStripWidth
        return (budget > 0 ? min(full, budget) : full).rounded()
    }

    /// Width of one wing as it is actually drawn — derived from the panel width the
    /// controller sized, so clamped Detailed text can never slide under the camera housing.
    static func stripWingWidth(metrics: Metrics, scale: CGFloat, style: CompactStyle) -> CGFloat {
        let width = compactWidth(metrics: metrics, scale: scale, style: style)
        return max(0, ((width - metrics.notchWidth) / 2).rounded())
    }

    /// Height one card occupies: cards grow with the font so two-line titles never clip,
    /// and the folder path adds a third line.
    static func rowHeight(contentFontSize: CGFloat, showsPath: Bool) -> CGFloat {
        IslandTheme.rowHeight
            + max(0, contentFontSize - 12.5) * 3
            + (showsPath ? IslandTheme.rowPathExtra : 0)
    }

    /// How many cards fit before the list would outgrow its height budget.
    static func visibleRows(maxPanelHeight: CGFloat, rowHeight: CGFloat) -> Int {
        let chrome = IslandTheme.listPad * 2 + IslandTheme.newButtonHeight + IslandTheme.toolbarHeight + 8
        let usable = max(maxPanelHeight - chrome, rowHeight)
        return max(1, min(Int(usable / rowHeight), IslandTheme.miniRowCount))
    }

    @MainActor
    static func rowHeight(prefs: Preferences) -> CGFloat {
        rowHeight(contentFontSize: CGFloat(prefs.contentFontSize), showsPath: prefs.showPathsInRows)
    }

    /// The one row count both sides must agree on: the panel is sized for exactly this
    /// many cards, so the view drawing more would push them off the bottom edge.
    @MainActor
    static func visibleRows(prefs: Preferences) -> Int {
        visibleRows(maxPanelHeight: CGFloat(prefs.maxPanelHeight), rowHeight: rowHeight(prefs: prefs))
    }

    static func size(
        for mode: IslandUIState.Mode,
        metrics: Metrics,
        widthScale: CGFloat,
        sessionRows: Int,
        pendingRows: Int = 0,
        rowHeight: CGFloat = IslandTheme.rowHeight,
        panelWidth: CGFloat = IslandTheme.activityWidth,
        maxPanelHeight: CGFloat = IslandTheme.boardMinHeight,
        compactStyle: CompactStyle = .clean
    ) -> CGSize {
        let scale = max(0.9, min(widthScale, 1.2))
        let strip = metrics.stripHeight

        switch mode {
        case .compact:
            let width = compactWidth(metrics: metrics, scale: scale, style: compactStyle)
            return CGSize(width: width, height: strip)

        case .activity:
            // Hover board: strip + session cards + New
            let w = (panelWidth * scale).rounded()
            let rows = min(max(sessionRows, 1), IslandTheme.miniRowCount)
            // Each waiting session grows an inline Allow/Deny row under its card.
            let decisions = CGFloat(min(pendingRows, rows)) * (IslandTheme.actionRowHeight + 6)
            let list =
                CGFloat(rows) * rowHeight
                + decisions
                + IslandTheme.listPad * 2
                + IslandTheme.newButtonHeight
                + 8
            return CGSize(width: w, height: (strip + min(list, maxPanelHeight)).rounded())

        case .expanded:
            let w = (panelWidth * scale).rounded()
            let height = max(maxPanelHeight, IslandTheme.boardMinHeight)
            return CGSize(width: w, height: (strip + height).rounded())
        }
    }
}
