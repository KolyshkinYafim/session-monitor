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
            button.action = #selector(clicked)
            button.target = self
            button.toolTip = "Session Monitor"
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

    @objc private func clicked() {
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
        menu.addItem(withTitle: "Show Island", action: #selector(expand), keyEquivalent: "")
        menu.addItem(withTitle: "Hide in menu bar", action: #selector(tuck), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func expand() { panel.expand() }
    @objc private func tuck() { panel.tuck() }
    @objc private func quit() { NSApp.terminate(nil) }

    func updateBadge() {
        guard let button = statusItem.button else { return }
        let count = store.waitingCount
        button.title = count > 0 ? " \(count)" : ""
        // NOTE: do NOT pulse/re-order the panel here. This runs on a 500ms poll, and pulsing
        // reset the 10s auto-tuck timer every half-second (so it never fired) and re-ordered
        // the panel constantly. The pulse is driven from AppController's status-change handler
        // on a *real* waiting_input transition instead.
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

    deinit { observationTask?.cancel() }
}
