import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<VibeIslandView>?
    private let store: SessionStore
    private let ui = IslandUIState()
    private let bridgePath: String
    private let onQuit: () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var currentSize = CGSize(width: 168, height: 36)

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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
    }

    func toggleExpanded() {
        if ui.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func expand() {
        ui.expand()
        applySize(animated: true)
        panel?.makeKey()
        installKeyMonitor()
    }

    func collapse() {
        ui.collapse()
        applySize(animated: true)
        removeKeyMonitor()
    }

    func pulseForWaiting() {
        if store.waitingCount > 0, !ui.isExpanded {
            // Keep collapsed but ensure visible on top
            panel?.orderFrontRegardless()
        }
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
            bridgePath: bridgePath,
            onSizeChange: { [weak self] size in
                self?.currentSize = size
                self?.applySize(animated: true)
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
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        hostingView?.frame = NSRect(origin: .zero, size: currentSize)
    }

    private func reposition() {
        applySize(animated: false)
    }

    /// Pins the island to the physical top-center (notch / menu bar center).
    private func topCenterFrame(size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }

        let full = screen.frame
        // Prefer docking into the top unsafe area (notch / camera housing) when present.
        let topSafe = screen.safeAreaInsets.top
        let gapBelowMenu: CGFloat = topSafe > 0 ? 2 : 4

        // On notched Macs, sit just under the status strip; otherwise under menu bar.
        let topY = full.maxY - gapBelowMenu
        let x = full.midX - size.width / 2
        let y = topY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.ui.isExpanded, let panel = self.panel else { return }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                DispatchQueue.main.async {
                    self.collapse()
                }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.ui.isExpanded, let panel = self.panel else { return event }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                self.collapse()
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            // keep local for keys separately - only clear mouse one
            self.localMonitor = nil
        }
    }

    private var keyMonitor: Any?

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
        if ui.isExpanded {
            collapse()
        }
    }
}
