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
    private var currentSize = CGSize(width: 158, height: 34)
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
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    func toggleExpanded() {
        if ui.mode == .expanded {
            ui.collapseToPill()
        } else {
            ui.expand()
        }
        applySize(animated: true)
        syncKeyMonitor()
        scheduleAutoTuck()
    }

    func expand() {
        ui.expand()
        applySize(animated: true)
        panel?.makeKey()
        syncKeyMonitor()
        scheduleAutoTuck()
    }

    func collapse() {
        ui.collapseToPill()
        applySize(animated: true)
        syncKeyMonitor()
        scheduleAutoTuck()
    }

    func tuck() {
        ui.tuck()
        applySize(animated: true)
        syncKeyMonitor()
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
        // Sit with menu bar chrome (curtain), above normal windows.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
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
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        hostingView?.frame = NSRect(origin: .zero, size: currentSize)
        syncKeyMonitor()
    }

    private func reposition() {
        applySize(animated: false)
    }

    /// Flush to the top edge so collapse feels like sliding into the menu-bar curtain.
    private func topCenterFrame(size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let full = screen.frame
        // 0 gap = tucked into top “curtain”; tiny offset only if needed for click targets.
        let topInset: CGFloat = ui.mode == .tucked ? 0 : 0
        let x = full.midX - size.width / 2
        let y = full.maxY - size.height - topInset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func scheduleAutoTuck() {
        autoTuckTimer?.invalidate()
        // Only auto-tuck when idle (no waiting) and not expanded.
        guard store.waitingCount == 0, ui.mode == .pill else { return }
        autoTuckTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.store.waitingCount == 0, self.ui.mode == .pill else { return }
                self.tuck()
            }
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.ui.mode == .expanded, let panel = self.panel else { return }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                DispatchQueue.main.async {
                    self.collapse()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func syncKeyMonitor() {
        if ui.mode == .expanded {
            installKeyMonitor()
        } else {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.collapse()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
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
