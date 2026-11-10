import Foundation

/// Normalisation shared by the index and the query, so both sides always
/// agree on what a word is. Only search keys are normalised; the text that
/// gets inserted never passes through here.
public enum SearchText {
    /// Lowercases and removes diacritics and width differences.
    public static func fold(_ text: String) -> String {
        // Unicode names and most keywords are plain ASCII; skip Foundation's
        // much slower folding for them.
        if let folded = foldASCII(text) {
            return folded
        }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func foldASCII(_ text: String) -> String? {
        var needsLowercasing = false
        for byte in text.utf8 {
            if byte >= 0x80 { return nil }
            if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
                needsLowercasing = true
            }
        }
        return needsLowercasing ? text.lowercased() : text
    }

    /// Splits folded text into words. Anything that is not a letter or a
    /// digit separates words, so `up-right arrow` and `up right arrow` yield
    /// the same three tokens.
    public static func tokens(_ folded: String) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var current: [UInt8] = []
        if folded.utf8.allSatisfy({ $0 < 0x80 }) {
            for byte in folded.utf8 {
                if isASCIIAlphanumeric(byte) {
                    current.append(byte)
                } else if !current.isEmpty {
                    result.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            }
        } else {
            for scalar in folded.unicodeScalars {
                if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                    current.append(contentsOf: Array(String(scalar).utf8))
                } else if !current.isEmpty {
                    result.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// The words of a phrase joined by single spaces: the form in which two
    /// phrases are compared for an exact match.
    public static func canonical(_ tokens: [[UInt8]]) -> [UInt8] {
        var joined: [UInt8] = []
        for (index, token) in tokens.enumerated() {
            if index > 0 { joined.append(UInt8(ascii: " ")) }
            joined.append(contentsOf: token)
        }
        return joined
    }

    static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    /// True when the text holds at least one ASCII letter or digit.
    static func containsASCIIAlphanumeric(_ text: String) -> Bool {
        text.utf8.contains(where: isASCIIAlphanumeric)
    }

    /// Optimal string alignment distance (Levenshtein plus adjacent
    /// transposition), cut off once it exceeds `limit`.
    static func editDistance(_ a: [UInt8], _ b: UnsafeBufferPointer<UInt8>, limit: Int) -> Int {
        let n = a.count
        let m = b.count
        if abs(n - m) > limit { return limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }
        var previous2 = [Int](repeating: 0, count: m + 1)
        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previous2[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            swap(&previous2, &previous)
            swap(&previous, &current)
        }
        return previous[m]
    }
}

/// A query written as code points: `U+2192`, `u+1f469 u+200d u+1f4bb`, or the
/// bare hex `2192`.
public struct CodePointQuery: Equatable, Sendable {
    /// The scalars named by the query, in order.
    public let string: String
    /// True when at least one code point carried a `U+` prefix. A bare hex
    /// word such as `face` or `100` is also an ordinary word or number, so it
    /// is only ever a secondary reading.
    public let isExplicit: Bool

    /// Parses a whole query. Returns nil unless every part is a valid scalar
    /// value; one invalid part rejects the query rather than being skipped.
    public static func parse(_ query: String) -> CodePointQuery? {
        let parts = query.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        guard !parts.isEmpty, parts.count <= 16 else { return nil }
        var scalars = String.UnicodeScalarView()
        var explicit = false
        for part in parts {
            var digits = Substring(part)
            if digits.hasPrefix("U+") || digits.hasPrefix("u+") {
                digits = digits.dropFirst(2)
                explicit = true
            }
            guard digits.count >= 2, digits.count <= 6, digits.allSatisfy(\.isHexDigit),
                  let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) else {
                return nil
            }
            scalars.append(scalar)
        }
        return CodePointQuery(string: String(scalars), isExplicit: explicit)
    }
}
