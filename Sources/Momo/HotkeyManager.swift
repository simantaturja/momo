import Carbon
import AppKit

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void

    init(keyCode: UInt32 = 9, modifiers: UInt32 = UInt32(cmdKey | shiftKey), handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    /// Returns whether the global hotkey was successfully registered. Fails most
    /// commonly when another app already owns the same shortcut.
    @discardableResult
    func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mgr.handler()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354 /* 'PAST' */), id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if installStatus != noErr { NSLog("Momo: InstallEventHandler failed (OSStatus \(installStatus))") }
        if registerStatus != noErr { NSLog("Momo: RegisterEventHotKey failed (OSStatus \(registerStatus)) — shortcut likely already in use") }
        return installStatus == noErr && registerStatus == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
