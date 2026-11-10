import Foundation
import CharmsCore

/// One alias line from `Data/aliases.tsv`: the alias text and its item
/// strings in order of preference.
struct CuratedAlias {
    let text: String
    let items: [String]
    let lineNumber: Int
}

/// One row of `Data/extras.tsv`: a hand-added entry outside the coverage
/// rules.
struct ExtraRow {
    let scalars: [UInt32]
    let kind: CatalogEntry.Kind
    let group: String
    let name: String
    let keywords: [String]
    let lineNumber: Int
}

enum CuratedFiles {
    static let aliasesFileName = "aliases.tsv"
    static let extrasFileName = "extras.tsv"

    /// The kind letters, kept in sync with `CatalogFormat`.
    static let kindsByLetter: [Character: CatalogEntry.Kind] = [
        "e": .emoji, "v": .variant, "s": .symbol, "p": .punctuation,
        "l": .letter, "n": .number, "m": .mark, "z": .space
    ]

    // MARK: - aliases.tsv

    static func parseAliases(_ text: String) throws -> [CuratedAlias] {
        try SourceParsing.dataLines(text).map { line in
            let fields = line.text.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else {
                throw CatalogError.malformed(file: aliasesFileName, line: line.number,
                                             reason: "expected 'alias<TAB>items'")
            }
            let items = try fields[1].split(separator: " ").map { item in
                try parseItem(item, line: line.number)
            }
            return CuratedAlias(text: String(fields[0]), items: items, lineNumber: line.number)
        }
    }

    /// An item is a literal string, or `U+XXXX` notation with `+` joining
    /// several code points (`U+2764+U+FE0F`) for invisible or ambiguous
    /// characters. A malformed `U+` item is an error, never a silent literal.
    private static func parseItem(_ item: Substring, line: Int) throws -> String {
        guard item.hasPrefix("U+") else { return String(item) }
        let parts = item.components(separatedBy: "+")
        var scalars: [UInt32] = []
        for index in stride(from: 0, to: parts.count, by: 2) {
            guard index + 1 < parts.count, parts[index] == "U" else {
                throw CatalogError.malformed(file: aliasesFileName, line: line,
                                             reason: "invalid U+ item '\(item)'")
            }
            scalars.append(try SourceParsing.hex(Substring(parts[index + 1]),
                                                 file: aliasesFileName, line: line))
        }
        var view = String.UnicodeScalarView()
        for scalar in scalars {
            guard let value = Unicode.Scalar(scalar) else {
                throw CatalogError.malformed(file: aliasesFileName, line: line,
                                             reason: "surrogate in U+ item '\(item)'")
            }
            view.append(value)
        }
        return String(view)
    }

    // MARK: - extras.tsv

    static func parseExtras(_ text: String) throws -> [ExtraRow] {
        try SourceParsing.dataLines(text).map { line in
            let fields = line.text.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5 else {
                throw CatalogError.malformed(file: extrasFileName, line: line.number,
                                             reason: "expected 5 fields, found \(fields.count)")
            }
            guard fields[1].count == 1, let letter = fields[1].first, let kind = kindsByLetter[letter] else {
                throw CatalogError.malformed(file: extrasFileName, line: line.number,
                                             reason: "unknown kind letter '\(fields[1])'")
            }
            return ExtraRow(
                scalars: try SourceParsing.scalarList(fields[0], file: extrasFileName, line: line.number),
                kind: kind,
                group: String(fields[2]),
                name: String(fields[3]),
                keywords: fields[4].split(separator: "|").map(String.init),
                lineNumber: line.number
            )
        }
    }
}
