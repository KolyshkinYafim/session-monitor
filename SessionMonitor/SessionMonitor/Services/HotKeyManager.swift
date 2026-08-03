import AppKit
import Carbon

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onToggle: (() -> Void)?

    func register(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        manager.onToggle?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x534D4F4E), id: 1)
        // Cmd+Shift+A
        RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        // Carbon teardown is best-effort; main actor cleanup happens in AppController.stop
    }
}
