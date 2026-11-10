import Foundation

/// One key press that was delivered to another application, reduced to what
/// marker recognition needs. Nothing here is stored beyond the tiny state in
/// `TriggerRecognizer`, and nothing is logged.
public struct KeyObservation: Equatable, Sendable {
    /// The characters the key produced under the active layout. Empty for a
    /// dead key, an arrow, a function key and the like.
    public var characters: String
    public var isRepeat: Bool
    /// Command or Control was held, so the key was a shortcut, not text.
    public var isShortcut: Bool
    /// The application that received the key.
    public var processID: Int32
    public var timestamp: TimeInterval

    public init(characters: String, isRepeat: Bool = false, isShortcut: Bool = false, processID: Int32, timestamp: TimeInterval) {
        self.characters = characters
        self.isRepeat = isRepeat
        self.isShortcut = isShortcut
        self.processID = processID
        self.timestamp = timestamp
    }

    /// True when the key typed ordinary visible text or a space.
    public var isText: Bool {
        guard !characters.isEmpty, !isShortcut else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            // Control characters, and the private-use values AppKit assigns
            // to arrows and function keys, are commands rather than text.
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

/// Recognises the typed marker `::` from a stream of key observations.
///
/// The recogniser sees produced characters, never key positions, so it works
/// the same on a layout where the colon is a shifted key. It holds only a
/// "one colon so far" candidate, the application it was typed into and a
/// timestamp; it keeps no history of what was typed.
public struct TriggerRecognizer: Sendable {
    public static let marker = "::"
    /// The two colons must arrive within this interval.
    public static let interval: TimeInterval = 1.0

    public enum Outcome: Equatable, Sendable {
        case nothing
        /// The first colon was typed; a second one would complete the marker.
        case candidate
        /// The marker was completed in this application.
        case triggered(processID: Int32)
    }

    /// What preceded the first colon, as far as the key stream shows.
    public enum Boundary: Equatable, Sendable {
        /// Nothing is known (first key seen, or after a reset).
        case unknown
        /// A space, tab or line break was typed just before.
        case whitespace
        /// Visible text was typed just before, as in `std::`.
        case text
    }

    private struct Candidate: Sendable {
        var processID: Int32
        var timestamp: TimeInterval
        var boundary: Boundary
    }

    private var candidate: Candidate?
    private var previous: (processID: Int32, boundary: Boundary)?

    public init() {}

    public var hasCandidate: Bool { candidate != nil }

    /// What was typed just before the marker that last completed. `text`
    /// means the marker certainly follows visible text and can be dismissed
    /// without consulting the source; the other values still need the
    /// committed source text to be checked.
    public private(set) var lastBoundary: Boundary = .unknown

    public mutating func observe(_ key: KeyObservation) -> Outcome {
        guard key.characters == ":", !key.isShortcut else {
            candidate = nil
            remember(key)
            return .nothing
        }
        if key.isRepeat {
            // A held colon key produces a run of colons; that is not a marker.
            reset()
            return .nothing
        }
        if let first = candidate, first.processID == key.processID, key.timestamp - first.timestamp <= Self.interval, key.timestamp >= first.timestamp {
            lastBoundary = first.boundary
            reset()
            return .triggered(processID: key.processID)
        }
        let boundary: Boundary
        if let previous, previous.processID == key.processID {
            boundary = previous.boundary
        } else {
            boundary = .unknown
        }
        candidate = Candidate(processID: key.processID, timestamp: key.timestamp, boundary: boundary)
        // A third colon must not pair with the second, so the colon itself
        // counts as preceding text for whatever follows.
        previous = (key.processID, .text)
        return .candidate
    }

    /// Forgets everything. Called on focus, caret, application and input
    /// source changes, on mouse navigation, and when a session starts.
    public mutating func reset() {
        candidate = nil
        previous = nil
    }

    private mutating func remember(_ key: KeyObservation) {
        guard key.isText, !key.isRepeat else {
            // Arrows, deletions and shortcuts move the caret or change the
            // text in ways the key stream cannot describe.
            previous = nil
            return
        }
        let endsWithWhitespace = key.characters.unicodeScalars.last.map { $0.properties.isWhitespace } ?? false
        previous = (key.processID, endsWithWhitespace ? .whitespace : .text)
    }
}
