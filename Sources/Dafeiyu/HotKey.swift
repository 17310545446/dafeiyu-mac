import Carbon.HIToolbox
import Foundation

/// 全局热键:Carbon RegisterEventHotKey,不需要辅助功能权限。
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_K),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) -> OSStatus {
        if hotKeyRef != nil { unregister() }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.onFire?() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)

        guard installStatus == noErr else { return installStatus }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4446_5955), id: 1) // 'DFYU'
        return RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                   GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
