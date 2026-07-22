import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let store: SessionStore
    private let panel: IslandPanelController
    private var observationTask: Task<Void, Never>?

    init(store: SessionStore, panel: IslandPanelController) {
        self.store = store
        self.panel = panel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.imagePosition = .imageLeft
            button.action = #selector(toggle)
            button.target = self
            button.toolTip = "Session Monitor"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateBadge()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                self?.updateBadge()
            }
        }
    }

    var button: NSStatusBarButton? { statusItem.button }

    @objc private func toggle() {
        guard let event = NSApp.currentEvent else {
            panel.toggle(relativeTo: statusItem.button)
            return
        }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        panel.toggle(relativeTo: statusItem.button)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Session Monitor", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        panel.show(relativeTo: statusItem.button)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = store.waitingCount
        if count > 0 {
            button.title = " \(count)"
            button.appearsDisabled = false
        } else {
            button.title = ""
        }
    }

    private static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(ovalIn: inset)
            NSColor.controlAccentColor.setFill()
            path.fill()
            let inner = rect.insetBy(dx: 6, dy: 6)
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: inner).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    deinit {
        observationTask?.cancel()
    }
}
