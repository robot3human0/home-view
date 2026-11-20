import Carbon.HIToolbox
import Foundation

/// Global klaviatura yorliqlari (masalan ⌃⌥G). Carbon API Accessibility ruxsatisiz ishlaydi.
/// Tugma bosilganda .qorHotKey xabari yuboriladi (userInfo["id"] — yorliq raqami).
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5152_4C4B), id: id) // 'QRLK'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == 0, let ref {
            refs[id] = ref
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id: id) }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            if err == 0 {
                NotificationCenter.default.post(name: .qorHotKey, object: nil, userInfo: ["id": hotKeyID.id])
            }
            return 0
        }, 1, &spec, nil, nil)
    }
}
