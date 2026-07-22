import AppKit
import SwiftUI

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let store: SessionStore
    private let bridgePath: String
    private let onQuit: () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(store: SessionStore, bridgePath: String, onQuit: @escaping () -> Void) {
        self.store = store
        self.bridgePath = bridgePath
        self.onQuit = onQuit
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if isVisible {
            hide()
        } else {
            show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        let panel = ensurePanel()
        position(panel, relativeTo: statusButton)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 362, height: 422),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.animationBehavior = .utilityWindow

        let root = SessionListView(
            store: store,
            bridgePath: bridgePath,
            onHide: { [weak self] in self?.hide() },
            onQuit: onQuit
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 362, height: 422)
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo statusButton: NSStatusBarButton?) {
        let width: CGFloat = 362
        let height: CGFloat = 422
        let gap: CGFloat = 6

        if let button = statusButton, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            let x = screenRect.midX - width / 2
            let y = screenRect.minY - height - gap
            var frame = NSRect(x: x, y: y, width: width, height: height)
            if let screen = buttonWindow.screen ?? NSScreen.main {
                frame = clamp(frame, to: screen.visibleFrame, gap: gap)
            }
            panel.setFrame(frame, display: true)
            return
        }

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Top-center under menu bar / notch region
        let x = visible.midX - width / 2
        let y = visible.maxY - height - gap
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func clamp(_ frame: NSRect, to visible: NSRect, gap: CGFloat) -> NSRect {
        var f = frame
        if f.minX < visible.minX + gap {
            f.origin.x = visible.minX + gap
        }
        if f.maxX > visible.maxX - gap {
            f.origin.x = visible.maxX - gap - f.width
        }
        if f.minY < visible.minY + gap {
            f.origin.y = visible.minY + gap
        }
        if f.maxY > visible.maxY - gap {
            f.origin.y = visible.maxY - gap - f.height
        }
        return f
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible, let panel = self.panel else { return }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                DispatchQueue.main.async {
                    self.hide()
                }
            }
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
