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
        store.setStatusChangeHandler { [weak self] session, status, previous in
            self?.notifications.notifyIfNeeded(session: session, status: status, previous: previous)
            self?.statusItem?.updateBadge()
        }

        let panel = IslandPanelController(
            store: store,
            bridgePath: BridgePath.displayPath,
            onQuit: { NSApp.terminate(nil) }
        )
        self.panel = panel
        statusItem = StatusItemController(store: store, panel: panel)

        let mock = MockProducer(store: store)
        mock.start()
        self.mock = mock

        let bridge = ChatHubBridge(store: store)
        bridge.start()
        self.bridge = bridge

        hotKey.register { [weak self] in
            guard let self else { return }
            self.panel?.toggle(relativeTo: self.statusItem?.button)
        }
    }

    func stop() {
        hotKey.unregister()
        mock?.stop()
        bridge?.stop()
        panel?.hide()
    }
}
