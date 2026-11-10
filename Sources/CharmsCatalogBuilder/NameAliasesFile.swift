import Foundation

/// `NameAliases.txt`: formal aliases of types `correction`, `alternate` and
/// `abbreviation`, per code point, in file order. `control` and `figment`
/// entries are excluded because they describe controls and withdrawn names,
/// not names a person would type.
struct NameAliasesFile {
    /// Accepted alias types, anything else is ignored on purpose.
    static let wantedTypes: Set<String> = ["correction", "alternate", "abbreviation"]

    /// code point -> aliases in file order
    let aliases: [UInt32: [String]]

    static let fileName = "NameAliases.txt"

    static func parse(_ text: String) throws -> NameAliasesFile {
        var aliases: [UInt32: [String]] = [:]
        for line in SourceParsing.dataLines(text) {
            let fields = line.text.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 3 else {
                throw CatalogError.malformed(file: fileName, line: line.number,
                                             reason: "expected 3 fields, found \(fields.count)")
            }
            let codePoint = try SourceParsing.hex(fields[0], file: fileName, line: line.number)
            let type = String(SourceParsing.trimmed(fields[2]))
            guard wantedTypes.contains(type) else { continue }
            aliases[codePoint, default: []].append(String(SourceParsing.trimmed(fields[1])))
        }
        return NameAliasesFile(aliases: aliases)
    }
}
