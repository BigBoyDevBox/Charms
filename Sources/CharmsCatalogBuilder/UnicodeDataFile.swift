import Foundation

/// One row of `UnicodeData.txt`. Only the fields the catalogue uses are kept:
/// code point, name and general category.
struct UnicodeDataRow {
    let codePoint: UInt32
    let name: String
    let category: String
    let lineNumber: Int

    /// `<X, First>` / `<X, Last>` name prefix for algorithmically named ranges.
    var rangeLabel: (label: String, isFirst: Bool)? {
        guard name.hasPrefix("<") else { return nil }
        if name.hasSuffix(", First>") {
            return (String(name.dropFirst().dropLast(", First>".count)), true)
        }
        if name.hasSuffix(", Last>") {
            return (String(name.dropFirst().dropLast(", Last>".count)), false)
        }
        return nil
    }
}

enum UnicodeDataFile {
    static let fileName = "UnicodeData.txt"

    static func parse(_ text: String) throws -> [UnicodeDataRow] {
        try SourceParsing.dataLines(text).map { line in
            let fields = line.text.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 15 else {
                throw CatalogError.malformed(file: fileName, line: line.number,
                                             reason: "expected 15 fields, found \(fields.count)")
            }
            return UnicodeDataRow(
                codePoint: try SourceParsing.hex(fields[0], file: fileName, line: line.number),
                name: String(fields[1]),
                category: String(fields[2]),
                lineNumber: line.number
            )
        }
    }
}
