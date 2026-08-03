import AppKit
import SwiftUI

extension Notification.Name {
    static let sessionMonitorOpenSettings = Notification.Name("sessionMonitorOpenSettings")
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let prefs: Preferences
    private let onApplyDisplay: () -> Void
    private let onQuit: () -> Void

    init(prefs: Preferences, onApplyDisplay: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.prefs = prefs
        self.onApplyDisplay = onApplyDisplay
        self.onQuit = onQuit
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView(
            prefs: prefs,
            onApplyDisplay: onApplyDisplay,
            onQuit: onQuit
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Session Monitor Settings"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
