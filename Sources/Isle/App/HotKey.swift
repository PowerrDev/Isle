/*
 *  HotKey.swift
 *  Isle
 *
 *  A system-wide keyboard shortcut backed by Carbon's RegisterEventHotKey.
 *  Unlike an event tap, this requires no Accessibility permission and costs
 *  nothing while idle: the system calls back only when the combination is
 *  pressed.
 */

import Carbon.HIToolbox

final class HotKey {

    // MARK: Properties

    private static let signature = OSType(0x4953_4C45) /* 'ISLE' */
    private static var nextIdentifier: UInt32 = 1

    private let identifier: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // MARK: Lifecycle

    /**
     Registers a global shortcut.

     - Parameters:
       - keyCode: A virtual key code, such as `kVK_Space`.
       - modifiers: A Carbon modifier mask, such as `cmdKey` or `optionKey`.
       - action: Called on the main queue each time the shortcut is pressed.
     - Returns: `nil` when another process already owns the combination.
     */
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.identifier = Self.nextIdentifier
        self.action = action
        Self.nextIdentifier += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()

            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)

            /* Every registered handler sees every hot-key event; respond only to our own. */
            guard pressed.signature == HotKey.signature, pressed.id == hotKey.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
