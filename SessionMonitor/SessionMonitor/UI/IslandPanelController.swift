import AppKit
import QuartzCore
import SwiftUI

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
        panel?.makeKey()
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

        let panel = NSPanel(
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
        panel.becomesKeyOnlyIfNeeded = true
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
        let hosting = NSHostingView(rootView: root)
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
                self?.forceFlushTop()
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
        if abs(frame.maxY - full.maxY) > 0.5 || abs(frame.origin.y - targetY) > 0.5 {
            frame.origin.y = targetY
            frame.origin.x = full.midX - frame.width / 2
            panel.setFrame(frame, display: true)
        }
    }

    private func reposition() {
        applySize(animated: false)
    }

    /// Absolute top-center of the physical display (menu-bar / notch band).
    private func topCenterFrame(size: CGSize) -> NSRect {
        guard let screen = dockingScreen() else {
            return NSRect(origin: .zero, size: size)
        }
        let full = screen.frame
        // Top edge of window == top edge of screen. Zero gap.
        let x = full.midX - size.width / 2
        let y = full.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func dockingScreen() -> NSScreen? {
        // Prefer screen under the mouse; fallback main.
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
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

    func windowDidResignKey(_ notification: Notification) {
        if ui.mode == .expanded {
            collapse()
        }
    }
}
