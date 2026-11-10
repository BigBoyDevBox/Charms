import Foundation

/// Small helpers shared by the line-oriented Unicode source files. Every
/// check reports `file:line` so a malformed row points at its origin.
enum SourceParsing {
    /// Splits `text` into its lines, returning 1-based line numbers with each.
    /// Empty lines and `#` comments are dropped here; callers still see every
    /// remaining line, so nothing is skipped silently.
    static func dataLines(_ text: String) -> [(number: Int, text: Substring)] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" || $0 == "\r" })
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
                return (number: index + 1, text: Substring(trimmed))
            }
    }

    /// Parses a hexadecimal code point reference such as `1F44D`.
    static func hex(_ field: Substring, file: String, line: Int) throws -> UInt32 {
        guard let value = UInt32(field, radix: 16), value <= 0x10FFFF else {
            throw CatalogError.malformed(file: file, line: line, reason: "invalid code point '\(field)'")
        }
        return value
    }

    /// Parses a whitespace-separated list of code points (`1F469 200D 1F4BB`)
    /// that will be turned into a string, so surrogates are rejected here.
    static func scalarList(_ field: Substring, file: String, line: Int) throws -> [UInt32] {
        var scalars: [UInt32] = []
        for part in field.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let value = try hex(part, file: file, line: line)
            guard Unicode.Scalar(value) != nil else {
                throw CatalogError.malformed(file: file, line: line, reason: "surrogate \(part) cannot appear in a string")
            }
            scalars.append(value)
        }
        guard !scalars.isEmpty else {
            throw CatalogError.malformed(file: file, line: line, reason: "empty code point list")
        }
        return scalars
    }

    /// Trims ASCII spaces and tabs around a field.
    static func trimmed(_ field: Substring) -> Substring {
        var field = field
        while field.first == " " || field.first == "\t" { field = field.dropFirst() }
        while field.last == " " || field.last == "\t" { field = field.dropLast() }
        return field
    }
}
