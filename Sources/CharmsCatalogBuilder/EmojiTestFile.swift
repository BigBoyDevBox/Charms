import Foundation
import CharmsCore

/// One row of `emoji-test.txt` with the group context that applies to it.
struct EmojiTestRow {
    enum Status: String {
        case component
        case fullyQualified = "fully-qualified"
        case minimallyQualified = "minimally-qualified"
        case unqualified
    }

    let scalars: [UInt32]
    let status: Status
    /// The `E<version>` emoji age from the row comment.
    let age: UnicodeAge
    /// The name after the version in the row comment, already lowercase.
    let name: String
    /// `"<group>/<subgroup>"` from the enclosing comment lines.
    let group: String
    let lineNumber: Int

    var containsSkinTone: Bool { scalars.contains { SkinTone.isModifier($0) } }

    /// The family key: the sequence without skin-tone modifiers or U+FE0F.
    /// A base and each of its toned forms share one key.
    var familyKey: [UInt32] {
        scalars.filter { !SkinTone.isModifier($0) && $0 != 0xFE0F }
    }

    var string: String {
        var view = String.UnicodeScalarView()
        for scalar in scalars {
            guard let value = Unicode.Scalar(scalar) else { continue }
            view.append(value)
        }
        return String(view)
    }
}

struct EmojiTestFile {
    /// The `# Version:` value, for example `18.0`.
    let version: String
    /// Every data row in file order, all statuses included.
    let rows: [EmojiTestRow]

    var fullyQualified: [EmojiTestRow] { rows.filter { $0.status == .fullyQualified } }
}

enum EmojiTestParser {
    static let fileName = "emoji-test.txt"

    static func parse(_ text: String) throws -> EmojiTestFile {
        var version: String?
        var group: String?
        var subgroup: String?
        var rows: [EmojiTestRow] = []

        for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = number + 1
            let line = raw.drop(while: { $0 == " " })
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let comment = SourceParsing.trimmed(line.dropFirst())
                if let value = comment.stripPrefix("group:") {
                    group = String(SourceParsing.trimmed(value))
                    subgroup = nil
                } else if let value = comment.stripPrefix("subgroup:") {
                    subgroup = String(SourceParsing.trimmed(value))
                } else if let value = comment.stripPrefix("Version:") {
                    version = String(SourceParsing.trimmed(value))
                }
                continue
            }

            rows.append(try parseRow(line, lineNumber: lineNumber,
                                     group: group, subgroup: subgroup))
        }

        guard let version else {
            throw CatalogError.malformed(file: fileName, line: 0, reason: "missing '# Version:' header")
        }
        return EmojiTestFile(version: version, rows: rows)
    }

    private static func parseRow(_ line: Substring, lineNumber: Int,
                                 group: String?, subgroup: String?) throws -> EmojiTestRow {
        let halves = line.split(separator: "#", maxSplits: 1)
        guard halves.count == 2 else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "missing '# <glyph> E<version> <name>' comment")
        }
        let fields = halves[0].split(separator: ";")
        guard fields.count == 2 else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "expected '<scalars> ; <status>'")
        }
        let scalars = try SourceParsing.scalarList(fields[0], file: fileName, line: lineNumber)
        guard let status = EmojiTestRow.Status(rawValue: String(SourceParsing.trimmed(fields[1]))) else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "unknown qualification '\(SourceParsing.trimmed(fields[1]))'")
        }

        // The comment is "<glyph> E<version> <name>": the glyph may be several
        // scalars but contains no space, the version token starts with 'E',
        // and the name is everything after it.
        let tokens = SourceParsing.trimmed(halves[1]).split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard tokens.count >= 3 else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "comment needs glyph, version and name")
        }
        let versionToken = tokens[1]
        guard versionToken.hasPrefix("E"), let age = UnicodeAge(String(versionToken.dropFirst())) else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "invalid emoji version '\(versionToken)'")
        }
        let name = tokens.dropFirst(2).joined(separator: " ")
        guard let group, let subgroup else {
            throw CatalogError.malformed(file: fileName, line: lineNumber, reason: "row appears before its group/subgroup")
        }
        return EmojiTestRow(scalars: scalars, status: status, age: age, name: name,
                            group: "\(group)/\(subgroup)", lineNumber: lineNumber)
    }
}

private extension Substring {
    func stripPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
