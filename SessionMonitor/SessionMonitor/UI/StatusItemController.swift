import AppKit

/// Minimal accessory control (quit / toggle). Primary UI is the top-center island.
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
            button.toolTip = "Session Monitor (island lives under the notch)"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateBadge()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.updateBadge()
            }
        }
    }

    @objc private func toggle() {
        guard let event = NSApp.currentEvent else {
            panel.toggleExpanded()
            return
        }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        panel.toggleExpanded()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Expand Island", action: #selector(expand), keyEquivalent: "")
        menu.addItem(withTitle: "Collapse Island", action: #selector(collapse), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Session Monitor", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func expand() { panel.expand() }
    @objc private func collapse() { panel.collapse() }
    @objc private func quit() { NSApp.terminate(nil) }

    func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = store.waitingCount
        button.title = count > 0 ? " \(count)" : ""
        panel.pulseForWaiting()
    }

    private static func makeIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 4), xRadius: 6, yRadius: 6)
            NSColor.labelColor.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    deinit {
        observationTask?.cancel()
    }
}
