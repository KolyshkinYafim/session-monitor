import AppKit
import QuartzCore
import SwiftUI

/// Borderless panels report `canBecomeKey == false` by default, which blocked the island from
/// ever receiving Esc or text input. Forcing it makes the expanded board interactive so
/// `.onExitCommand` and the reply field work reliably — without requiring Accessibility.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Makes the island act on the *first* click even while it's in the background. Without this a
/// non-activating panel swallows the first click just to take focus (so rows/buttons need a
/// double click) — an ambient HUD should respond immediately, like Dynamic Island.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<VibeIslandView>?
    private let store: SessionStore
    private let ui = IslandUIState()
    private let commands = CommandBridge()
    private let bridgePath: String
    private let onQuit: () -> Void
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var currentSize = CGSize(width: 168, height: 24)
    private var autoTuckTimer: Timer?

    init(store: SessionStore, bridgePath: String, onQuit: @escaping () -> Void) {
        self.store = store
        self.bridgePath = bridgePath
        self.onQuit = onQuit
        super.init()
    }

    var isExpanded: Bool { ui.isExpanded }

    func start() {
        let panel = ensurePanel()
        reposition()
        panel.orderFrontRegardless()
        installClickOutsideMonitor()
        scheduleAutoTuck()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func stop() {
        autoTuckTimer?.invalidate()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    func toggleExpanded() {
        if ui.mode == .expanded {
            ui.collapseToPill()
        } else {
            ui.expand()
        }
        applySize(animated: true)
        scheduleAutoTuck()
    }

    func expand() {
        ui.expand()
        applySize(animated: true)
        scheduleAutoTuck()
    }

    func collapse() {
        ui.collapseToPill()
        applySize(animated: true)
        scheduleAutoTuck()
    }

    func tuck() {
        ui.tuck()
        applySize(animated: true)
    }

    func pulseForWaiting() {
        if store.waitingCount > 0, ui.mode == .tucked {
            ui.mode = .pill
            applySize(animated: true)
        }
        panel?.orderFrontRegardless()
        scheduleAutoTuck()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: currentSize.width, height: currentSize.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Must be ≥ status/menu level or macOS clamps the frame under the menu bar.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
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
            commands: commands,
            bridgePath: bridgePath,
            onSizeChange: { [weak self] size in
                self?.currentSize = size
                self?.applySize(animated: true)
                self?.scheduleAutoTuck()
            },
            onQuit: onQuit
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: currentSize)
        panel.contentView = hosting
        self.hostingView = hosting
        self.panel = panel
        return panel
    }

    private func applySize(animated: Bool) {
        guard let panel else { return }
        let frame = topCenterFrame(size: currentSize)
        // Keep level high every resize — some macOS builds demote panels.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.forceFlushTop() }
            }
        } else {
            panel.setFrame(frame, display: true)
            forceFlushTop()
        }
        hostingView?.frame = NSRect(origin: .zero, size: currentSize)
        panel.orderFrontRegardless()
    }

    /// Re-assert top-edge flush if the system nudged the frame.
    private func forceFlushTop() {
        guard let panel, let screen = dockingScreen() else { return }
        let full = screen.frame
        var frame = panel.frame
        let targetY = full.maxY - frame.height
        let targetX = clampedX(centeredWidth: frame.width, on: full)
        if abs(frame.maxY - full.maxY) > 0.5 || abs(frame.origin.x - targetX) > 0.5 {
            frame.origin.y = targetY
            frame.origin.x = targetX
            panel.setFrame(frame, display: true)
        }
    }

    private func reposition() {
        applySize(animated: false)
    }

    /// Absolute top-center of the docking display (menu-bar / notch band).
    private func topCenterFrame(size: CGSize) -> NSRect {
        guard let screen = dockingScreen() else {
            return NSRect(origin: .zero, size: size)
        }
        let full = screen.frame
        // Top edge of window == top edge of screen. Zero gap.
        let y = full.maxY - size.height
        return NSRect(x: clampedX(centeredWidth: size.width, on: full), y: y, width: size.width, height: size.height)
    }

    /// Horizontally centered on the display, but clamped inside its bounds so the panel can
    /// never land off-screen (the old code produced X≈-949 on displays left of the primary).
    private func clampedX(centeredWidth width: CGFloat, on full: NSRect) -> CGFloat {
        let centered = full.midX - width / 2
        return min(max(centered, full.minX), full.maxX - width)
    }

    private func dockingScreen() -> NSScreen? {
        // Always dock to the primary display — the one that owns the global origin (0,0) and the
        // menu bar. We deliberately do NOT follow the mouse: that made the island jump between
        // displays and pushed it off-screen (X≈-949) on a monitor positioned left of the primary.
        let screens = NSScreen.screens
        let primary = screens.first { $0.frame.origin == .zero }
        return primary ?? NSScreen.main ?? screens.first
    }

    /// Re-arm the auto-tuck countdown from a discrete activity change (e.g. the last waiting
    /// session just resolved). Safe to call from the status-change handler — it is NOT a poll,
    /// so it won't reset the timer every tick the way the old badge poll did.
    func refreshAutoTuck() {
        scheduleAutoTuck()
    }

    private func scheduleAutoTuck() {
        autoTuckTimer?.invalidate()
        guard store.waitingCount == 0, ui.mode == .pill else { return }
        autoTuckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.store.waitingCount == 0, self.ui.mode == .pill else { return }
                self.tuck()
            }
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
            .keyDown
        ]) { [weak self] event in
            guard let self else { return }
            if event.type == .keyDown, event.keyCode == 53, self.ui.mode == .expanded {
                DispatchQueue.main.async { self.collapse() }
                return
            }
            guard self.ui.mode == .expanded, let panel = self.panel else { return }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let mouse = NSEvent.mouseLocation
                if !panel.frame.contains(mouse) {
                    DispatchQueue.main.async { self.collapse() }
                }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.ui.mode == .expanded {
                self.collapse()
                return nil
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // NOTE: intentionally no `windowDidResignKey` auto-collapse. As a non-activating accessory
    // panel we never hold app activation, so relying on key-resignation made expand→collapse
    // race (the panel would bounce shut the instant it opened). Click-outside is handled
    // deterministically by the global mouse monitor below instead.
}
