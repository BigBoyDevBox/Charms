import CoreGraphics
import Foundation

/// Raw rectangles read from the source application around the caret, in
/// AppKit global coordinates. Each one is geometry only; none of them carries
/// document text.
public struct CaretProbe: Equatable, Sendable {
    /// Bounds of the zero-length range at the caret (or at the end of a
    /// non-empty selection).
    public var caret: CGRect?
    /// Bounds of the character just before that position.
    public var previousCharacter: CGRect?
    /// Bounds of the character just after that position.
    public var nextCharacter: CGRect?
    /// Bounds of a non-empty selection.
    public var selection: CGRect?

    public init(caret: CGRect? = nil, previousCharacter: CGRect? = nil, nextCharacter: CGRect? = nil, selection: CGRect? = nil) {
        self.caret = caret
        self.previousCharacter = previousCharacter
        self.nextCharacter = nextCharacter
        self.selection = selection
    }
}

/// Where the caret is, as well as it can be known without reading text.
public struct CaretEstimate: Equatable, Sendable {
    public enum Evidence: String, Sendable {
        /// The next character starts at the caret's X, so the caret is on its line.
        case confirmedByNextCharacter
        /// The previous character ends at the caret's X, so the caret is on its line.
        case confirmedByPreviousCharacter
        /// Only the zero-length rectangle is known.
        case unconfirmed
        /// No zero-length rectangle; inferred from the previous character.
        case previousCharacterOnly
        /// No zero-length rectangle; inferred from the next character.
        case nextCharacterOnly
    }

    /// The caret: zero width, one line tall.
    public let line: CGRect
    /// The region the picker must leave uncovered. Equal to `line` when the
    /// line is confirmed, taller when the caret might be one line lower.
    public let keepVisible: CGRect
    public let evidence: Evidence

    public init(line: CGRect, keepVisible: CGRect, evidence: Evidence) {
        self.line = line
        self.keepVisible = keepVisible
        self.evidence = evidence
    }
}

/// Turns raw caret rectangles into a trustworthy anchor.
///
/// Measured on macOS 27 (TextEdit, TextKit): the rectangle for a zero-length
/// range comes back exactly one line too high, while rectangles for real
/// characters are right. Another project measured that Chrome reports a caret
/// after a trailing newline at the end of the previous line. A picker placed
/// "below the caret" from the raw rectangle would then cover the very line
/// being typed. So the caret's line is taken from an adjacent character when
/// that character demonstrably touches the caret horizontally, and otherwise
/// one extra line below the reported rectangle is kept clear.
public enum CaretGeometry {
    /// Caret rectangles shorter or taller than this are not carets: tiny ones
    /// are placeholders, huge ones are whole fields or documents.
    public static let plausibleHeights: ClosedRange<CGFloat> = 4...300
    /// How closely a neighbouring character must meet the caret horizontally.
    static let horizontalTolerance: CGFloat = 1.5
    /// Extra room around the containing window or field.
    static let containerSlop: CGFloat = 8
    /// A selection up to this many lines tall is kept visible as a whole.
    static let selectionLineLimit: CGFloat = 4

    /// - Parameters:
    ///   - probe: Rectangles around the caret, AppKit coordinates.
    ///   - container: The focused window (preferred) or field. A caret
    ///     outside it is stale or scrolled out of view.
    public static func estimate(_ probe: CaretProbe, container: CGRect?) -> CaretEstimate? {
        let caret = probe.caret.flatMap { plausible($0, in: container) ? $0 : nil }
        let previous = probe.previousCharacter.flatMap { plausible($0, in: container) && $0.width > 0.5 ? $0 : nil }
        let next = probe.nextCharacter.flatMap { plausible($0, in: container) ? $0 : nil }

        guard let estimate = lineEstimate(caret: caret, previous: previous, next: next) else { return nil }
        guard let selection = probe.selection, selection.isFinite, selection.height > 0,
              selection.height <= estimate.line.height * selectionLineLimit,
              plausibleContainer(selection, in: container) else {
            return estimate
        }
        return CaretEstimate(line: estimate.line, keepVisible: bounding(estimate.keepVisible, selection), evidence: estimate.evidence)
    }

    /// The smallest rectangle containing both. Unlike `CGRect.union`, this is
    /// well defined for the zero-width rectangles carets are made of.
    static func bounding(_ a: CGRect, _ b: CGRect) -> CGRect {
        let minX = min(a.minX, b.minX)
        let minY = min(a.minY, b.minY)
        return CGRect(x: minX, y: minY, width: max(a.maxX, b.maxX) - minX, height: max(a.maxY, b.maxY) - minY)
    }

    private static func lineEstimate(caret: CGRect?, previous: CGRect?, next: CGRect?) -> CaretEstimate? {
        if let caret {
            if let next, abs(next.minX - caret.minX) <= horizontalTolerance, isNear(next, caret) {
                let line = CGRect(x: caret.minX, y: next.minY, width: 0, height: next.height)
                return CaretEstimate(line: line, keepVisible: line, evidence: .confirmedByNextCharacter)
            }
            if let previous, abs(previous.maxX - caret.minX) <= horizontalTolerance, isNear(previous, caret) {
                let line = CGRect(x: caret.minX, y: previous.minY, width: 0, height: previous.height)
                return CaretEstimate(line: line, keepVisible: line, evidence: .confirmedByPreviousCharacter)
            }
            let line = CGRect(x: caret.minX, y: caret.minY, width: 0, height: caret.height)
            return CaretEstimate(line: line, keepVisible: bounding(line, lineBelow(line)), evidence: .unconfirmed)
        }
        if let previous {
            // The caret follows this character, on its line or, after a wrap
            // or newline, at the start of the next one.
            let line = CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
            return CaretEstimate(line: line, keepVisible: bounding(line, lineBelow(line)), evidence: .previousCharacterOnly)
        }
        if let next {
            let line = CGRect(x: next.minX, y: next.minY, width: 0, height: next.height)
            return CaretEstimate(line: line, keepVisible: line, evidence: .nextCharacterOnly)
        }
        return nil
    }

    /// The same rectangle one line further down the page. In AppKit
    /// coordinates down is towards smaller Y.
    private static func lineBelow(_ line: CGRect) -> CGRect {
        line.offsetBy(dx: 0, dy: -line.height)
    }

    /// An adjacent character further than a couple of lines from the reported
    /// caret is unrelated geometry, not a correction.
    private static func isNear(_ character: CGRect, _ caret: CGRect) -> Bool {
        abs(character.midY - caret.midY) <= 2.5 * max(character.height, caret.height)
    }

    static func plausible(_ rect: CGRect, in container: CGRect?) -> Bool {
        guard rect.isFinite, rect.width >= 0, plausibleHeights.contains(rect.height) else { return false }
        return plausibleContainer(rect, in: container)
    }

    private static func plausibleContainer(_ rect: CGRect, in container: CGRect?) -> Bool {
        guard let container, container.isFinite, container.width > 0, container.height > 0 else { return true }
        // The vertical allowance covers a caret reported one line off.
        let allowed = container.insetBy(dx: -containerSlop, dy: -(rect.height + containerSlop))
        // A zero-width rectangle never "intersects" in CoreGraphics terms, so
        // test its centre line instead.
        let probe = CGRect(x: rect.minX - 0.5, y: rect.minY, width: max(rect.width, 1), height: rect.height)
        return allowed.intersects(probe)
    }
}
