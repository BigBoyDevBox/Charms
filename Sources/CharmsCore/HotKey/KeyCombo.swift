import Foundation

/// A global shortcut: one key position plus modifiers.
///
/// The key is stored as a virtual key code, a position on the keyboard, since
/// that is what the system's hot-key registration takes. What is printed on
/// that key depends on the active layout, so the label is supplied by the
/// caller and never derived from the code here.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// The symbols in the order macOS menus print them.
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control-P: the key in the position ANSI keyboards label P.
    public static let standard = KeyCombo(keyCode: 35, modifiers: .control)

    public enum Problem: Equatable, Sendable {
        /// A plain or Shift-only key would swallow ordinary typing.
        case needsModifier
        /// The combination is an editing or system command that must keep
        /// working everywhere.
        case reserved
    }

    /// Why this combination must not be registered, or nil when it may be
    /// tried.
    ///
    /// - Parameter keyCharacter: What the key types under the active layout,
    ///   without modifiers. Reserved commands are defined by that character:
    ///   on a Swiss German keyboard Undo is the key ANSI calls Y.
    public func problem(keyCharacter: String?) -> Problem? {
        let isFunctionKey = Self.functionKeyNumbers[keyCode] != nil
        if modifiers.isDisjoint(with: [.control, .option, .command]), !isFunctionKey {
            return .needsModifier
        }
        if modifiers == .command || modifiers == [.command, .shift] {
            if let character = keyCharacter?.lowercased(), Self.reservedCommandCharacters.contains(character) {
                return .reserved
            }
            if Self.reservedCommandKeyCodes.contains(keyCode) {
                return .reserved
            }
        }
        if modifiers == [.command, .option], keyCode == Self.escapeKeyCode {
            return .reserved
        }
        return nil
    }

    /// The shortcut as menus show it, such as `⌃P`.
    public func displayString(keyCharacter: String?) -> String {
        modifiers.symbols + Self.keyLabel(keyCode: keyCode, keyCharacter: keyCharacter)
    }

    /// A label for the key alone.
    public static func keyLabel(keyCode: UInt16, keyCharacter: String?) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let number = functionKeyNumbers[keyCode] {
            return "F\(number)"
        }
        if let keyCharacter, !keyCharacter.isEmpty, !keyCharacter.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 }) {
            return keyCharacter.uppercased()
        }
        return "Key \(keyCode)"
    }

    static let escapeKeyCode: UInt16 = 53

    /// Command combinations every text field depends on.
    private static let reservedCommandCharacters: Set<String> = ["q", "w", "h", "m", "c", "v", "x", "z", "a"]
    /// Command-Tab and Command-Space, by position.
    private static let reservedCommandKeyCodes: Set<UInt16> = [48, 49]

    private static let specialKeyLabels: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    private static let functionKeyNumbers: [UInt16: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20
    ]
}
