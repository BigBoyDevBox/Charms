import Foundation

/// How a chosen string travels to the source application.
public enum InsertionBackend: String, Codable, Equatable, Sendable, CaseIterable {
    /// One keyboard event carrying the whole string. Leaves the clipboard
    /// alone. Measured on macOS 27 in TextEdit: complete strings of up to 64
    /// UTF-16 units arrive intact, a selection is replaced, and one Undo
    /// removes the insertion.
    case unicodeEvents
    /// Write the string to the clipboard and send Paste. For applications
    /// that ignore the text carried by a keyboard event.
    case paste
}

public enum InsertionPolicy {
    /// Longest string sent as a single keyboard event. Every catalogue entry
    /// is far shorter; anything longer goes out in whole-character pieces.
    public static let maximumUnitsPerEvent = 64

    /// The backend for an application: the user's explicit choice, otherwise
    /// keyboard events. The choice is made before anything is sent and is
    /// never changed afterwards, since a second attempt could insert twice.
    public static func backend(forBundleIdentifier bundleIdentifier: String?, pasteApplications: Set<String>) -> InsertionBackend {
        guard let bundleIdentifier else { return .unicodeEvents }
        return BundlePattern.matches(bundleIdentifier, in: pasteApplications) ? .paste : .unicodeEvents
    }

    /// Splits text into pieces of at most `maximumUnitsPerEvent` UTF-16
    /// units without ever cutting through a character: a surrogate pair, a
    /// joined emoji sequence or a base with its combining marks stays whole.
    public static func eventPayloads(for text: String, limit: Int = maximumUnitsPerEvent) -> [[UInt16]] {
        var payloads: [[UInt16]] = []
        var current: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > limit {
                payloads.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty {
            payloads.append(current)
        }
        return payloads
    }
}

/// Matches bundle identifiers against a user-editable list. An entry ending
/// in `.*` covers every identifier with that prefix, as in `com.jetbrains.*`.
public enum BundlePattern {
    public static func matches(_ bundleIdentifier: String, in patterns: Set<String>) -> Bool {
        if patterns.contains(bundleIdentifier) { return true }
        for pattern in patterns where pattern.hasSuffix(".*") {
            let prefix = pattern.dropLast(1)
            if bundleIdentifier.hasPrefix(prefix) { return true }
        }
        return false
    }
}

/// Decides when the keys that committed a choice have been let go.
///
/// Focus must not return to the source while Return, a mouse button or a
/// modifier is still down: the source would receive the key-up, an
/// auto-repeated Return, or apply the modifier to the inserted text.
public struct ReleaseGate: Equatable, Sendable {
    public static let deadline: TimeInterval = 1.0

    public struct Inputs: Equatable, Sendable {
        public var modifiersDown: Bool
        public var commitKeyDown: Bool
        public var mouseButtonDown: Bool

        public init(modifiersDown: Bool, commitKeyDown: Bool, mouseButtonDown: Bool) {
            self.modifiersDown = modifiersDown
            self.commitKeyDown = commitKeyDown
            self.mouseButtonDown = mouseButtonDown
        }

        public var allReleased: Bool { !modifiersDown && !commitKeyDown && !mouseButtonDown }
    }

    public enum Verdict: Equatable, Sendable {
        case wait
        case released
        case expired
    }

    public let start: TimeInterval

    public init(start: TimeInterval) {
        self.start = start
    }

    public func evaluate(_ inputs: Inputs, now: TimeInterval) -> Verdict {
        if inputs.allReleased { return .released }
        return now - start >= Self.deadline ? .expired : .wait
    }
}

/// What is known about the field a session was opened for, compared with
/// what is true just before dispatch.
public struct TargetCheck: Equatable, Sendable {
    public var accessibilityTrusted: Bool
    public var secureInputActive: Bool
    /// The captured application is still running under the same launch.
    public var sameProcess: Bool
    /// The captured application is the one receiving keys again.
    public var processIsFrontmost: Bool
    /// The application's focused element is the captured one.
    public var sameElement: Bool
    /// The captured element is, or has become, a secure field.
    public var elementIsSecure: Bool
    /// The selection still is what capture saw; nil when it cannot be read.
    public var selectionUnchanged: Bool?

    public init(accessibilityTrusted: Bool, secureInputActive: Bool, sameProcess: Bool, processIsFrontmost: Bool, sameElement: Bool, elementIsSecure: Bool, selectionUnchanged: Bool?) {
        self.accessibilityTrusted = accessibilityTrusted
        self.secureInputActive = secureInputActive
        self.sameProcess = sameProcess
        self.processIsFrontmost = processIsFrontmost
        self.sameElement = sameElement
        self.elementIsSecure = elementIsSecure
        self.selectionUnchanged = selectionUnchanged
    }

    public enum Failure: String, Equatable, Sendable, CaseIterable {
        case accessibilityRevoked
        case secureInput
        case processGone
        case processNotFrontmost
        case focusMoved
        case secureField
        case selectionChanged
    }

    /// The first reason this target must not receive text, or nil.
    public var failure: Failure? {
        if !accessibilityTrusted { return .accessibilityRevoked }
        if secureInputActive { return .secureInput }
        if !sameProcess { return .processGone }
        if !processIsFrontmost { return .processNotFrontmost }
        if !sameElement { return .focusMoved }
        if elementIsSecure { return .secureField }
        if selectionUnchanged == false { return .selectionChanged }
        return nil
    }

    /// Whether the picker can still usefully stay open for copying after
    /// this failure, or the context is gone.
    public var validation: ValidationResult {
        guard let failure else { return .valid }
        switch failure {
        case .processGone, .processNotFrontmost:
            return .invalid
        case .accessibilityRevoked, .secureInput, .focusMoved, .secureField, .selectionChanged:
            return .copyOnly
        }
    }
}

/// Guards the clipboard while the paste backend borrows it.
///
/// The previous contents are put back only if nothing else has written to
/// the clipboard since this transaction's own write, and only once. A new
/// transaction cannot start while one is unresolved, so a restoration can
/// never act on behalf of a later session.
public struct ClipboardRestoreGuard: Equatable, Sendable {
    public private(set) var pending: Pending?

    public struct Pending: Equatable, Sendable {
        public let session: SessionID
        /// The clipboard's change count right after our write.
        public let changeCount: Int
    }

    public init() {}

    public var canBegin: Bool { pending == nil }

    /// Records a transaction. Returns false, changing nothing, when one is
    /// still pending.
    @discardableResult
    public mutating func begin(session: SessionID, changeCountAfterWrite: Int) -> Bool {
        guard pending == nil else { return false }
        pending = Pending(session: session, changeCount: changeCountAfterWrite)
        return true
    }

    /// Ends the transaction and says whether the saved contents may be
    /// written back. False when someone copied something in the meantime.
    public mutating func resolve(session: SessionID, currentChangeCount: Int) -> Bool {
        guard let transaction = pending, transaction.session == session else { return false }
        pending = nil
        return transaction.changeCount == currentChangeCount
    }

    /// Drops the transaction without restoring, for example at quit.
    public mutating func abandon() {
        pending = nil
    }
}
