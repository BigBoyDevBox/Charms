import AppKit
import Carbon.HIToolbox

/// A global hot key registered with Carbon's `RegisterEventHotKey`.
///
/// This API needs no privacy permission, unlike an event tap, and delivers
/// the key to Charms alone. Registration, teardown and the callbacks all
/// happen on the main thread, which is why `Sendable` can be asserted.
final class CarbonHotKey: @unchecked Sendable {
    /// Called on the main thread for each press, once per physical press.
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isDown = false
    private var lastPress: TimeInterval = 0

    /// Four-character signature 'CHRM'.
    private static let signature: OSType = 0x4348_524D
    private static let identifier: UInt32 = 1

    deinit { unregister() }

    var isRegistered: Bool { hotKeyRef != nil }

    @discardableResult
    func register(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            // Claim only our own hot key, so a handler installed by anything
            // else on the same target still sees its events.
            guard pressed.signature == CarbonHotKey.signature, pressed.id == CarbonHotKey.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            let kind = GetEventKind(event)
            DispatchQueue.main.async { hotKey.handle(kind: kind) }
            return noErr
        }
        let installed = InstallEventHandler(
            GetApplicationEventTarget(), callback, eventTypes.count, &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        guard installed == noErr else { return false }

        let identifier = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registered = RegisterEventHotKey(keyCode, carbonModifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            // Leave no handler behind for a hot key that does not exist.
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isDown = false
    }

    private func handle(kind: UInt32) {
        if kind == UInt32(kEventHotKeyReleased) {
            isDown = false
            return
        }
        // Holding the shortcut must not toggle the picker again and again.
        // Should a release ever go missing, a press long after the last one
        // is still accepted.
        let now = ProcessInfo.processInfo.systemUptime
        if isDown, now - lastPress < 1.5 { return }
        isDown = true
        lastPress = now
        onPressed?()
    }
}
