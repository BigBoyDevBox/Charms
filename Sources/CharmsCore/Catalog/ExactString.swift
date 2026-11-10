import Foundation

/// A string compared and hashed by its exact Unicode scalars.
///
/// Swift's `String ==` uses canonical equivalence, so `"\u{212B}"` (ANGSTROM
/// SIGN) equals `"\u{C5}"` (Å) and `"\u{2126}"` (OHM SIGN) equals `"Ω"`. The
/// catalogue, favourites and recents identify an item by the precise sequence
/// that will be inserted, so they must not conflate those.
public struct ExactString: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public static func == (lhs: ExactString, rhs: ExactString) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        for byte in value.utf8 {
            hasher.combine(byte)
        }
    }

    public var description: String { value }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public extension String {
    /// Identity of this string as an exact scalar sequence.
    var exact: ExactString { ExactString(self) }

    /// True when both strings consist of the same Unicode scalars in the same
    /// order, without canonical-equivalence folding.
    func isExactly(_ other: String) -> Bool {
        utf8.elementsEqual(other.utf8)
    }

    /// Code points in the conventional notation, for example `U+1F469 U+200D U+1F4BB`.
    var codePointDescription: String {
        unicodeScalars.map { CodePoint.format($0.value) }.joined(separator: " ")
    }
}

public enum CodePoint {
    /// Formats a scalar value as `U+XXXX`, padded to at least four hex digits.
    public static func format(_ value: UInt32) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }

    /// Bare uppercase hex without the `U+` prefix, padded to four digits.
    public static func hex(_ value: UInt32) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }
}
