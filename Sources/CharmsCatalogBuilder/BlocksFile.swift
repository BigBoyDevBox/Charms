import Foundation

/// `Blocks.txt`: the block table plus the Unicode release in its header
/// (`# Blocks-18.0.0.txt`), which UnicodeData.txt itself does not carry.
struct BlocksFile {
    let unicodeVersion: String
    let blocks: RangeTable<String>
}

enum BlocksParser {
    static let fileName = "Blocks.txt"

    static func parse(_ text: String) throws -> BlocksFile {
        var version: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            let line = SourceParsing.trimmed(raw)
            guard line.hasPrefix("#") else { break }
            let comment = SourceParsing.trimmed(line.dropFirst())
            if comment.hasPrefix("Blocks-"), comment.hasSuffix(".txt") {
                version = String(comment.dropFirst("Blocks-".count).dropLast(".txt".count))
            }
        }
        guard let version else {
            throw CatalogError.malformed(file: fileName, line: 0, reason: "missing '# Blocks-<version>.txt' header")
        }
        let blocks = try RangeTableParser.parse(text, file: fileName) { value, _ in String(value) }
        return BlocksFile(unicodeVersion: version, blocks: blocks)
    }
}
