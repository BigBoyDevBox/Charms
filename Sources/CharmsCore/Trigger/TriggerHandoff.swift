import Foundation

/// Tracks what the user typed after `::` while keyboard focus was moving from
/// the source application to the picker.
///
/// A listening observer cannot stop keys from reaching the source, so the
/// first letters of `::arrow` may land there before the picker is key.
/// Measured on macOS 27: a global key monitor reports exactly the keys that
/// were delivered to other applications, in order, and the picker's own field
/// receives the rest. So the delivery channel itself says which side got each
/// key: everything observed here went to the source, and forms the beginning
/// of the query. The committed source text is still read back and compared
/// before anything is replaced, because an observed key says where a key
/// went, not what text it produced.
public struct TriggerHandoff: Equatable, Sendable {
    /// Longest query prefix that may accumulate on the source side.
    public static let maximumPrefixUTF16Length = 64

    public enum Problem: String, Equatable, Sendable {
        /// A deletion, arrow, Return or shortcut reached the source after the
        /// marker; the text there can no longer be predicted.
        case sourceEdited
        /// Whitespace or a line break followed the marker in the source, as
        /// in `x :: Int`. The marker was ordinary text.
        case whitespaceAfterMarker
        case prefixTooLong
    }

    /// Characters typed after the marker that were delivered to the source.
    public private(set) var sourcePrefix = ""
    public private(set) var problem: Problem?

    public init() {}

    /// The text that must sit directly before the caret in the source.
    public var expectedText: String { TriggerRecognizer.marker + sourcePrefix }

    /// Length of `expectedText` in the UTF-16 units Accessibility ranges use.
    public var expectedUTF16Length: Int { expectedText.utf16.count }

    /// Records a key that was delivered to the source after the marker.
    public mutating func sourceReceived(_ key: KeyObservation) {
        guard problem == nil else { return }
        guard key.isText, !key.isRepeat else {
            problem = .sourceEdited
            return
        }
        if key.characters.unicodeScalars.contains(where: { $0.properties.isWhitespace }) {
            problem = .whitespaceAfterMarker
            return
        }
        guard sourcePrefix.utf16.count + key.characters.utf16.count <= Self.maximumPrefixUTF16Length else {
            problem = .prefixTooLong
            return
        }
        sourcePrefix += key.characters
    }

    public enum Verdict: Equatable, Sendable {
        /// The source holds exactly the marker and prefix at an allowed
        /// boundary; `range` is what to replace, in UTF-16 units.
        case verified(location: Int, length: Int)
        /// The source text is not what was typed. Nothing may be replaced.
        case mismatch
        /// The marker follows visible text, as in `std::`.
        case notAtBoundary
        /// The source has not caught up with the observed keys yet.
        case incomplete
    }

    /// Compares a reading of the source with what was observed.
    ///
    /// - Parameters:
    ///   - caretLocation: The collapsed selection's location, UTF-16 units.
    ///   - textBeforeCaret: The `expectedUTF16Length` units before the caret,
    ///     or fewer when the field holds less text.
    ///   - precedingCharacter: The character just before those, nil at the
    ///     start of the field.
    public func verify(caretLocation: Int, textBeforeCaret: String, precedingCharacter: String?) -> Verdict {
        guard problem == nil else { return .mismatch }
        let expected = expectedText
        guard textBeforeCaret.isExactly(expected) else {
            // While keys are still in flight the source shows a prefix of the
            // expected text, ending at its caret.
            return Self.isProperPrefixEnding(textBeforeCaret, of: expected) ? .incomplete : .mismatch
        }
        let length = expectedUTF16Length
        guard caretLocation >= length else { return .mismatch }
        if let precedingCharacter, !precedingCharacter.isEmpty {
            let isBoundary = precedingCharacter.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
            guard isBoundary else { return .notAtBoundary }
        }
        return .verified(location: caretLocation - length, length: length)
    }

    /// True when `text` ends with a non-empty proper prefix of `expected`:
    /// the source has processed only the first keys so far.
    private static func isProperPrefixEnding(_ text: String, of expected: String) -> Bool {
        let expectedUnits = Array(expected.utf16)
        let textUnits = Array(text.utf16)
        guard !textUnits.isEmpty else { return true }
        for length in stride(from: min(expectedUnits.count - 1, textUnits.count), to: 0, by: -1) {
            if textUnits.suffix(length).elementsEqual(expectedUnits.prefix(length)) {
                return true
            }
        }
        return false
    }

    /// The full query: what reached the source, followed by what the picker's
    /// own field received.
    public func query(pickerText: String) -> String {
        sourcePrefix + pickerText
    }
}

/// Whether typed-trigger recognition may run right now, and if not, why.
public struct TriggerEligibility: Equatable, Sendable {
    public enum Blocker: String, Equatable, Sendable, CaseIterable {
        case disabled
        case accessibilityMissing
        case secureInput
        case sessionActive
        case inputMethodActive
        case excludedApplication
        case ownApplication
    }

    public var isEnabled: Bool
    public var hasAccessibility: Bool
    public var isSecureInputActive: Bool
    public var isSessionActive: Bool
    /// The active input source composes text (an input method) instead of
    /// being a plain keyboard layout. Committed text cannot be inferred from
    /// key presses there.
    public var isInputMethodActive: Bool

    public init(isEnabled: Bool, hasAccessibility: Bool, isSecureInputActive: Bool, isSessionActive: Bool, isInputMethodActive: Bool) {
        self.isEnabled = isEnabled
        self.hasAccessibility = hasAccessibility
        self.isSecureInputActive = isSecureInputActive
        self.isSessionActive = isSessionActive
        self.isInputMethodActive = isInputMethodActive
    }

    /// Conditions that decide whether the observer should be installed at
    /// all. With any of these present no keyboard observation takes place.
    public var observerBlocker: Blocker? {
        if !isEnabled { return .disabled }
        if !hasAccessibility { return .accessibilityMissing }
        return nil
    }

    /// Why a marker typed into `bundleIdentifier` must be ignored, or nil
    /// when it may open the picker.
    public func blocker(forBundleIdentifier bundleIdentifier: String?, ownBundleIdentifier: String?, exclusions: Set<String>) -> Blocker? {
        if let blocker = observerBlocker { return blocker }
        if isSecureInputActive { return .secureInput }
        if isSessionActive { return .sessionActive }
        if isInputMethodActive { return .inputMethodActive }
        guard let bundleIdentifier else { return nil }
        if bundleIdentifier == ownBundleIdentifier { return .ownApplication }
        if BundlePattern.matches(bundleIdentifier, in: exclusions) { return .excludedApplication }
        return nil
    }
}
