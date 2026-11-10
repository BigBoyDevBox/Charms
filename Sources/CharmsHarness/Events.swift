import AppKit
import CoreGraphics

/// Posts keyboard and mouse input the way hardware does.
enum Events {
    /// Keys that sit in the same place on every layout. Letters are never
    /// sent by key code: the code for "z" on one layout is "y" on another.
    static let namedKeys: [String: CGKeyCode] = [
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]

    private static let modifierKeys: [(name: String, flag: CGEventFlags, keyCode: CGKeyCode)] = [
        ("control", .maskControl, 59), ("option", .maskAlternate, 58),
        ("shift", .maskShift, 56), ("command", .maskCommand, 55)
    ]

    /// A process that posts events and exits at once loses them (measured
    /// on macOS 27), so every posting command waits this long before it
    /// reports.
    static let lingerMicroseconds: useconds_t = 300_000

    private static func source() -> CGEventSource? {
        CGEventSource(stateID: .hidSystemState)
    }

    private static func post(keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, text: String? = nil) {
        guard let event = CGEvent(keyboardEventSource: source(), virtualKey: keyCode, keyDown: down) else {
            Output.fail("could not create a keyboard event")
        }
        event.flags = flags
        if let text {
            let units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        event.post(tap: .cghidEventTap)
    }

    /// Presses the modifiers, then the key, then releases in reverse order.
    ///
    /// The modifier keys are pressed for real rather than only flagged on
    /// the key event: a flag without its key leaves the session believing
    /// the modifier is still held, which is not what a keyboard does and
    /// defeats code that waits for the keys to be released.
    static func press(keyCode: CGKeyCode, arguments: Arguments, holdMilliseconds: Double = 0) {
        let held = modifierKeys.filter { arguments.has($0.name) }
        var flags: CGEventFlags = []
        for modifier in held {
            flags.insert(modifier.flag)
            post(keyCode: modifier.keyCode, down: true, flags: flags)
            usleep(15_000)
        }
        post(keyCode: keyCode, down: true, flags: flags)
        usleep(useconds_t(max(holdMilliseconds, 20) * 1000))
        post(keyCode: keyCode, down: false, flags: flags)
        for modifier in held.reversed() {
            usleep(15_000)
            flags.remove(modifier.flag)
            post(keyCode: modifier.keyCode, down: false, flags: flags)
        }
        usleep(lingerMicroseconds)
    }

    /// Types text as Unicode key events, which do not depend on the layout.
    static func type(_ text: String, gapMilliseconds: Double) {
        for character in text {
            post(keyCode: 0, down: true, flags: [], text: String(character))
            post(keyCode: 0, down: false, flags: [], text: String(character))
            usleep(useconds_t(max(gapMilliseconds, 1) * 1000))
        }
        usleep(lingerMicroseconds)
    }

    static func moveMouse(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: source(), mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(lingerMicroseconds)
    }

    static func click(at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source(), mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(30_000)
        }
        usleep(lingerMicroseconds)
    }
}
