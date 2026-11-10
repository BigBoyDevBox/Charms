import Carbon.HIToolbox
import Foundation

/// Answers questions about the active keyboard layout.
///
/// A shortcut is stored as a key position, but what is printed on that key,
/// and which position means Paste, depends on the layout. On a Swiss German
/// keyboard the positions ANSI calls Y and Z are swapped, so nothing here
/// assumes ANSI labels.
enum KeyLayout {
    /// The character a key produces with the given Carbon modifiers.
    static func character(forKeyCode keyCode: UInt16, carbonModifiers: UInt32 = 0) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(pointer, to: CFData.self) as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            // The translation keeps its own dead-key state; it never touches
            // the state of the application the user is typing in.
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), (carbonModifiers >> 8) & 0xFF,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }

    /// The key position that types `character` while Command is held. This
    /// is the position an application's Command shortcut answers to, which
    /// differs from the plain position on layouts such as Dvorak-QWERTY.
    static func keyCode(producing character: String, carbonModifiers: UInt32) -> UInt16? {
        for keyCode in UInt16(0)..<UInt16(127) {
            if let produced = self.character(forKeyCode: keyCode, carbonModifiers: carbonModifiers),
               produced.lowercased() == character {
                return keyCode
            }
        }
        return nil
    }

    /// True when the selected input source composes text, as the Japanese,
    /// Chinese and Korean input methods do, instead of being a plain layout.
    /// Key presses then do not say what text was committed.
    static var isInputMethodActive: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else {
            return false
        }
        let type = unsafeBitCast(pointer, to: CFString.self)
        return !CFEqual(type, kTISTypeKeyboardLayout)
    }
}
