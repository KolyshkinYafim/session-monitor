import AppKit
import QuartzCore
import SwiftUI

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view with safe-area zero + mouse enter/exit for Vibe-like hover expand.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // No .assumeInside — it caused enter/exit thrash while the panel resized.
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect,
            .mouseMoved
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingView: FirstMouseHostingView<VibeIslandView>?
    private let store: SessionStore
    private let ui = IslandUIState()
    private let commands = CommandBridge()
    private let prefs: Preferences
    private let bridgePath: String
    private let onQuit: () -> Void
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var storeObservation: Task<Void, Never>?
    private var currentSize = CGSize(width: 280, height: 40)
    private var leaveTimer: Timer?
    /// A resize we skipped because the pointer was inside — applied once it leaves.
    private var pendingRefit = false
    private var enterTimer: Timer?
    private var dwellTimer: Timer?
    private var isMorphing = false

    init(store: SessionStore, prefs: Preferences, bridgePath: String, onQuit: @escaping () -> Void) {
        self.store = store
        self.prefs = prefs
        self.bridgePath = bridgePath
        self.onQuit = onQuit
        super.init()
    }

    func applyPreferences() { recalculateSize(animated: false) }
    var isExpanded: Bool { ui.isExpanded }

    func start() {
        // Default: compact strip (Vibe). Hover opens the list.
        ui.compact()
        _ = ensurePanel()
        // Ordering in is `updateVisibility`'s call, not ours: on a fullscreen docking
        // screen the strip must never flash before the first poll tick hides it.
        recalculateSize(animated: false)
        installClickOutsideMonitor()

        storeObservation = Task { [weak self] in
            var previousDecisions = 0
            var lastShape = (waiting: -1, rows: -1, decisions: -1)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                // Fullscreen is screen state, not store state: nothing publishes it, so it
                // has to be re-read every tick or the strip stays on top of a fullscreen
                // window until the next session event happens to arrive.
                self.updateVisibility()
                let rows = self.displaySessions
                let shape = (
                    waiting: self.store.waitingCount,
                    rows: rows.count,
                    decisions: rows.filter { $0.pending != nil }.count
                )
                guard shape != lastShape else { continue }
                let wasQuiet = lastShape.waiting <= 0
                lastShape = shape
                // Rising edge of "someone needs you" peeks the list open…
                if shape.waiting > 0, wasQuiet, self.ui.mode == .compact, self.prefs.autoExpandOnWaiting,
                   !self.shouldSuppressAutoReveal {
                    self.ui.presentForWaiting()
                    self.startAutoRevealDwell()
                }
                // …and any change in row/decision count has to re-fit the panel, or the
                // inline Allow/Deny row gets clipped off the bottom.
                //
                // Except while the pointer is inside: resizing under the cursor makes the
                // panel swim and moves the card out from under a click. A new decision row
                // still re-fits — that one the user must be able to reach.
                if self.ui.mode != .compact {
                    let pointerInside = self.ui.isHovering
                        || (self.panel?.frame.contains(NSEvent.mouseLocation) ?? false)
                    let decisionsChanged = shape.decisions != previousDecisions
                    if !pointerInside || decisionsChanged {
                        self.recalculateSize(animated: true)
                    } else {
                        self.pendingRefit = true
                    }
                }
                previousDecisions = shape.decisions
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recalculateSize(animated: false) }
        }
    }

    func stop() {
        leaveTimer?.invalidate()
        enterTimer?.invalidate()
        dwellTimer?.invalidate()
        storeObservation?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    func toggleExpanded() {
        if ui.mode == .expanded { collapse() } else { expand() }
    }

    func expand() {
        dwellTimer?.invalidate()
        ui.expand()
        recalculateSize(animated: true)
    }

    func collapse() {
        if ui.isHovering || store.waitingCount > 0 {
            ui.collapseToActivity()
        } else {
            ui.compact()
        }
        recalculateSize(animated: true)
    }

    func compact() {
        dwellTimer?.invalidate()
        ui.compact()
        recalculateSize(animated: true)
    }

    /// Explicit click on the strip: opens the list whatever `hoverExpand` says — the
    /// preference is about the pointer dwelling, not about the island being clickable.
    func openList() {
        guard ui.mode == .compact else { return }
        // A deliberate click outlives the dwell of whatever event opened the peek before it.
        dwellTimer?.invalidate()
        ui.collapseToActivity()
        recalculateSize(animated: true)
    }

    func pulseForWaiting() {
        if store.waitingCount > 0 {
            if prefs.autoExpandOnWaiting, !shouldSuppressAutoReveal {
                ui.presentForWaiting()
                startAutoRevealDwell()
            }
            ui.triggerAttentionPulse()
            recalculateSize(animated: true)
        }
        panel?.level = IslandGeometry.panelLevel
        updateVisibility(reassert: true)
    }

    /// Vibe's "Expand panel for completion notifications": the finished turn peeks the list
    /// open for `autoRevealDwell` instead of only glowing. Off by default, so a user who
    /// wants glow only never sees the panel move.
    func presentForCompletion() {
        guard prefs.expandForCompletion, ui.mode == .compact else { return }
        ui.presentForCompletion()
        startAutoRevealDwell()
        recalculateSize(animated: true)
        updateVisibility(reassert: true)
    }

    func refreshCompactSchedule() {
        // After waiting clears: if not hovering and not pinned, return to compact strip.
        guard ui.mode != .expanded, !ui.pinExpanded else { return }
        if store.waitingCount == 0, !ui.isHovering {
            ui.compact()
            recalculateSize(animated: true)
        }
    }

    // MARK: - Auto reveal

    /// The user is already looking at the agent that asked: its terminal is the frontmost
    /// app, so covering that window with a peek hides the very prompt it announces. The
    /// sound and the badge still fire — only the takeover is skipped.
    private var shouldSuppressAutoReveal: Bool {
        guard prefs.smartSuppression else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        let waiting = store.sessions.filter { $0.status == .waitingInput && !$0.isMock }
        // All of them, not any: a second agent waiting in a window the user cannot see is
        // exactly the case the reveal exists for.
        return !waiting.isEmpty && waiting.allSatisfy { $0.focusApp == front }
    }

    private func startAutoRevealDwell() {
        dwellTimer?.invalidate()
        let dwell = prefs.autoRevealDwell
        // 0 = the reveal stays until the user or the waiting state dismisses it.
        guard dwell > 0 else { return }
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.autoRevealDwellExpired() }
        }
    }

    private func autoRevealDwellExpired() {
        guard ui.openedByEvent, ui.mode == .activity, !ui.pinExpanded else {
            ui.openedByEvent = false
            return
        }
        // Pointer inside means the peek became a real hover: collapsing under the cursor
        // would pull the card out from under a click, so hand it to the leave timer.
        let pointerInside = ui.isHovering || (panel?.frame.contains(NSEvent.mouseLocation) ?? false)
        ui.openedByEvent = false
        guard !pointerInside else { return }
        ui.compact()
        recalculateSize(animated: true)
    }

    // MARK: - Hover

    private func handleHover(_ inside: Bool) {
        leaveTimer?.invalidate()
        if !inside { enterTimer?.invalidate() }
        if inside {
            ui.isHovering = true
            // Deliberately no makeKey here: a non-activating panel still pulls key from
            // the window the user is typing in, and hover has no text target, so those
            // keystrokes vanish. Cards stay clickable through `acceptsFirstMouse`.
            guard prefs.hoverExpand else { return }
            guard ui.mode != .expanded else { return }
            // Ignore thrash mid-morph (resize often fires fake mouseExited).
            if isMorphing { return }
            if ui.mode == .compact {
                // Open on a short dwell, not on every pointer that crosses the strip.
                enterTimer?.invalidate()
                enterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let panel = self.panel else { return }
                        guard panel.frame.contains(NSEvent.mouseLocation) else { return }
                        guard self.ui.mode == .compact else { return }
                        self.ui.collapseToActivity()
                        self.recalculateSize(animated: true)
                    }
                }
            }
        } else {
            // Debounce leave — and re-check pointer is still outside the panel frame.
            scheduleLeaveCheck(after: max(0.05, min(prefs.hoverLeaveDelay, 1.5)))
        }
    }

    private func scheduleLeaveCheck(after delay: TimeInterval) {
        leaveTimer?.invalidate()
        leaveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // A leave landing mid-morph has to be retried, never dropped: the pointer
                // is already outside, so no second mouseExited is coming and the island
                // would stay expanded forever.
                if self.isMorphing {
                    self.scheduleLeaveCheck(after: IslandTheme.morphDuration)
                    return
                }
                if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) {
                    self.ui.isHovering = true
                    return
                }
                self.ui.isHovering = false
                if self.pendingRefit {
                    self.pendingRefit = false
                    self.recalculateSize(animated: false)
                }
                guard !self.ui.pinExpanded, self.ui.mode != .expanded else { return }
                // A waiting session holds the peek open only while its reveal is still
                // within dwell; after that the pointer leaving means what it always means.
                if self.ui.openedByEvent, self.store.waitingCount > 0, self.prefs.autoExpandOnWaiting {
                    return
                }
                if self.ui.mode == .activity {
                    self.ui.compact()
                    self.recalculateSize(animated: true)
                }
            }
        }
    }

    // MARK: - Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: currentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = IslandGeometry.panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self
        panel.animationBehavior = .none

        let root = VibeIslandView(
            store: store,
            ui: ui,
            prefs: prefs,
            commands: commands,
            bridgePath: bridgePath,
            onExpand: { [weak self] in self?.expand() },
            onCollapse: { [weak self] in self?.collapse() },
            onCompact: { [weak self] in self?.compact() },
            onOpenList: { [weak self] in self?.openList() },
            onQuit: onQuit,
            onHoverChange: { [weak self] inside in self?.handleHover(inside) }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.onHover = { [weak self] inside in
            Task { @MainActor in self?.handleHover(inside) }
        }
        hosting.frame = NSRect(origin: .zero, size: currentSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hostingView = hosting
        self.panel = panel
        return panel
    }

    private func recalculateSize(animated: Bool) {
        guard let screen = IslandGeometry.dockingScreen(preferredName: prefs.screenName) else { return }
        let metrics = IslandGeometry.metrics(
            for: screen,
            notchWidthOffset: CGFloat(prefs.notchWidthOffset),
            notchHeightOffset: CGFloat(prefs.notchHeightOffset)
        )
        // The view can't observe NSScreen, so it reads the metrics from here instead.
        if ui.metrics != metrics { ui.metrics = metrics }
        let size = IslandGeometry.size(
            for: ui.mode,
            metrics: metrics,
            widthScale: prefs.widthStyle.scale,
            sessionRows: displaySessions.count,
            pendingRows: displaySessions.filter { $0.pending != nil }.count,
            rowHeight: IslandGeometry.rowHeight(prefs: prefs),
            panelWidth: CGFloat(prefs.panelWidth),
            maxPanelHeight: CGFloat(prefs.maxPanelHeight),
            compactStyle: prefs.compactStyle
        )
        currentSize = size
        applyFrame(size: size, on: screen, animated: animated)
    }

    private func applyFrame(size: CGSize, on screen: NSScreen, animated: Bool) {
        guard let panel else { return }
        let frame = IslandGeometry.topCenterFrame(size: size, on: screen)
        panel.level = IslandGeometry.panelLevel

        if animated {
            isMorphing = true
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            panel.setFrame(panel.frame, display: false)
            NSAnimationContext.endGrouping()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = IslandTheme.morphDuration
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1.0)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                // Re-resolve the screen instead of capturing it: NSScreen isn't Sendable,
                // and by the time this fires the display set may have changed anyway.
                Task { @MainActor in
                    guard let self else { return }
                    self.isMorphing = false
                    if let current = IslandGeometry.dockingScreen(preferredName: self.prefs.screenName) {
                        self.forceFlushTop(on: current)
                    }
                }
            }
        } else {
            panel.setFrame(frame, display: true)
            forceFlushTop(on: screen)
        }
        hostingView?.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        updateVisibility(reassert: true)
    }

    /// Only the expanded board earns key status — its reply field has to receive typing.
    /// Compact and hover have no text target, so holding key there would swallow
    /// keystrokes meant for whatever app the user is actually working in.
    private func syncKeyWindow() {
        guard let panel, panel.isVisible else { return }
        if ui.mode == .expanded {
            if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
        } else if panel.isKeyWindow {
            // Nothing hands key back directly; ordering out and straight back in lets
            // AppKit return it to the frontmost app's window.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    /// "Hide when idle" only applies to the resting strip — anything live, hovered or
    /// expanded stays on screen, otherwise the island would vanish mid-interaction.
    /// Fullscreen hides unconditionally: the panel floats above the fullscreen window, so
    /// leaving it up for a waiting session would break the one thing fullscreen is for.
    ///
    /// `reassert` re-orders an already visible panel back to the front — needed after a
    /// morph, not on the poll tick, where re-ordering every 400 ms is pure churn.
    private func updateVisibility(reassert: Bool = false) {
        guard let panel else { return }
        let quiet = store.islandSessions.isEmpty && store.waitingCount == 0
        let idleHidden = prefs.hideWhenEmpty && quiet && ui.mode == .compact && !ui.isHovering
        // The expanded board is summoned by hand (⌘⇧A) — hiding that one would make the
        // hotkey look broken inside a fullscreen app.
        let fullscreenHidden = isDockingScreenFullscreen && ui.mode != .expanded
        if idleHidden || fullscreenHidden {
            if panel.isVisible { panel.orderOut(nil) }
        } else if reassert || !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private var isDockingScreenFullscreen: Bool {
        guard prefs.hideInFullscreen,
              let screen = IslandGeometry.dockingScreen(preferredName: prefs.screenName)
        else { return false }
        return IslandGeometry.isFullscreenSpace(screen)
    }

    private func forceFlushTop(on screen: NSScreen) {
        guard let panel else { return }
        let target = IslandGeometry.topCenterFrame(size: currentSize, on: screen)
        panel.setFrame(target, display: true)
        hostingView?.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: currentSize)
        panel.level = IslandGeometry.panelLevel
        updateVisibility(reassert: true)
        // After the morph, never during it: the re-order below would cut the animation.
        syncKeyWindow()
    }

    /// Same count VibeIslandView draws — the panel is sized for exactly these rows.
    private var displaySessions: [SessionMeta] {
        Array(store.islandSessions.prefix(IslandGeometry.visibleRows(prefs: prefs)))
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .keyDown
        ]) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown, event.keyCode == 53 {
                DispatchQueue.main.async {
                    if self.ui.mode == .expanded { self.collapse() }
                    else if self.ui.mode == .activity { self.compact() }
                }
                return
            }
            // Only collapse *expanded* board on outside click — not the hover list
            // (outside-click during hover felt broken / “sticky then snap”).
            guard self.ui.mode == .expanded, let panel = self.panel else { return }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    DispatchQueue.main.async { self.collapse() }
                }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                if self.ui.mode == .expanded { self.collapse(); return nil }
                if self.ui.mode == .activity { self.compact(); return nil }
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }
}
