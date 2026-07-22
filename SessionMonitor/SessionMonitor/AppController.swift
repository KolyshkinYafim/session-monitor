import AppKit

@MainActor
final class AppController {
    let store = SessionStore()
    private let notifications = NotificationService()
    private var mock: MockProducer?
    private var bridge: ChatHubBridge?
    private var statusItem: StatusItemController?
    private var panel: IslandPanelController?
    private let hotKey = HotKeyManager()

    func start() {
        notifications.requestAuthorization()

        let panel = IslandPanelController(
            store: store,
            bridgePath: BridgePath.displayPath,
            onQuit: { NSApp.terminate(nil) }
        )
        self.panel = panel

        store.setStatusChangeHandler { [weak self] session, status, previous in
            // Don't spam OS notifs for demo mock sessions.
            if !session.isMock {
                self?.notifications.notifyIfNeeded(session: session, status: status, previous: previous)
            }
            self?.statusItem?.updateBadge()
            if status == .waitingInput, !session.isMock {
                self?.panel?.pulseForWaiting()
            }
        }

        panel.start()
        statusItem = StatusItemController(store: store, panel: panel)

        // Mock only when explicitly enabled — otherwise badge jumps 1/2 randomly.
        let mockEnabled =
            ProcessInfo.processInfo.environment["SESSION_MONITOR_MOCK"] == "1"
        if mockEnabled {
            let mock = MockProducer(store: store)
            mock.start()
            self.mock = mock
        }

        let bridge = ChatHubBridge(store: store)
        bridge.start()
        self.bridge = bridge

        hotKey.register { [weak self] in
            self?.panel?.toggleExpanded()
        }
    }

    func stop() {
        hotKey.unregister()
        mock?.stop()
        bridge?.stop()
        panel?.stop()
    }
}
