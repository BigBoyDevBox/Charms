import Foundation
import CharmsCore

/// The outcome of a catalogue build: the encodable contents plus the
/// statistics for the manifest.
public struct CatalogBuildResult {
    public let contents: CatalogFormat.Contents
    public let statistics: CatalogStatistics

    public init(contents: CatalogFormat.Contents, statistics: CatalogStatistics) {
        self.contents = contents
        self.statistics = statistics
    }
}

/// Builds `CatalogFormat.Contents` from the pinned Unicode, Emoji and CLDR
/// sources: emoji first in `emoji-test.txt` order, then the listed
/// characters in code point order, then `extras.tsv`; `aliases.tsv` ranks are
/// applied last, and the result is validated before it is returned.
public enum CatalogBuilder {
    /// The format characters listed as kind `space`: soft hyphen, zero width
    /// space/joiners, bidi marks, word joiner and the byte order mark.
    private static let spaceFormats: Set<UInt32> = [
        0x00AD, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0xFEFF
    ]

    /// Emoji components that are never useful on their own: skin tones,
    /// regional indicator letters, hair components and variation selectors.
    private static let emojiComponentRanges: [(first: UInt32, last: UInt32)] = [
        (0x1F3FB, 0x1F3FF), (0x1F1E6, 0x1F1FF), (0x1F9B0, 0x1F9B3),
        (0xFE00, 0xFE0F), (0xE0100, 0xE01EF)
    ]

    /// Range labels from UnicodeData.txt mapped to their naming rule. The
    /// hex prefixes are the ones the Unicode Standard assigns in
    /// `extracted/DerivedName.txt` (lines like `4E00..9FFF ; CJK UNIFIED
    /// IDEOGRAPH-*`); an unlisted letter/number range label is a build error.
    private static let rangeRules: [String: CodePointRange.NameRule] = [
        "CJK Ideograph": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension A": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension B": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension C": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension D": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension E": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension F": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension G": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension H": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension I": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "CJK Ideograph Extension J": .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
        "Hangul Syllable": .hangulSyllable,
        "Tangut Ideograph": .hexSuffix(prefix: "TANGUT IDEOGRAPH-"),
        "Tangut Ideograph Supplement": .hexSuffix(prefix: "TANGUT IDEOGRAPH-"),
        "Jurchen Character": .hexSuffix(prefix: "JURCHEN CHARACTER-"),
        "Seal Character": .hexSuffix(prefix: "SMALL SEAL CHARACTER-")
    ]

    /// Scripts that promote a character to rank 3.
    private static let commonScripts: Set<String> = ["Latin", "Greek", "Cyrillic", "Common", "Inherited"]

    public static func build(_ sources: CatalogSources) throws -> CatalogBuildResult {
        let unicodeData = try UnicodeDataFile.parse(sources.unicodeData)
        let blocksFile = try BlocksParser.parse(sources.blocks)
        let scripts = try RangeTableParser.parse(sources.scripts, file: "Scripts.txt") { value, line in
            let script = String(value)
            guard !script.isEmpty else {
                throw CatalogError.malformed(file: "Scripts.txt", line: line, reason: "empty script name")
            }
            return script
        }
        let ages = try RangeTableParser.parse(sources.derivedAge, file: "DerivedAge.txt") { value, line in
            guard let age = UnicodeAge(String(value)) else {
                throw CatalogError.malformed(file: "DerivedAge.txt", line: line, reason: "invalid age '\(value)'")
            }
            return age
        }
        let nameAliases = try NameAliasesFile.parse(sources.nameAliases)
        let emojiFile = try EmojiTestParser.parse(sources.emojiTest)
        let cldr = try CldrAnnotationsParser.parse(
            annotations: sources.annotations, annotationsFile: "annotations-en.json",
            derived: sources.annotationsDerived, derivedFile: "annotations-derived-en.json")
        let curatedAliases = try CuratedFiles.parseAliases(sources.aliases)
        let extras = try CuratedFiles.parseExtras(sources.extras)

        var session = Session(blocks: blocksFile.blocks, scripts: scripts, ages: ages,
                              nameAliases: nameAliases, cldr: cldr)
        try session.emitEmoji(fullyQualified: emojiFile.fullyQualified)
        try session.emitCharacters(rows: unicodeData)
        try session.emitExtras(extras)
        try session.applyAliases(curatedAliases)
        try session.validate(expectedEmojiCount: emojiFile.fullyQualified.count)

        let contents = CatalogFormat.Contents(
            header: CatalogFormat.Header(
                unicodeVersion: blocksFile.unicodeVersion,
                emojiVersion: emojiFile.version,
                cldrVersion: cldr.version),
            entries: session.entries,
            ranges: session.ranges)
        let statistics = try session.statistics(contents: contents, aliasCount: curatedAliases.count)
        return CatalogBuildResult(contents: contents, statistics: statistics)
    }

    // MARK: - Character inclusion rules

    private static func hexList(_ scalars: [UInt32]) -> String {
        scalars.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
    }

    private static func isListed(_ category: String) -> Bool {
        guard let first = category.first else { return false }
        return "LMNPS".contains(first) || category == "Zs"
    }

    private static func isEmojiComponent(_ codePoint: UInt32) -> Bool {
        emojiComponentRanges.contains { codePoint >= $0.first && codePoint <= $0.last }
    }

    private static func isNoncharacter(_ value: UInt32) -> Bool {
        (value & 0xFFFE) == 0xFFFE || (0xFDD0...0xFDEF).contains(value)
    }

    // MARK: - Build state

    private struct Session {
        let blocks: RangeTable<String>
        let scripts: RangeTable<String>
        let ages: RangeTable<UnicodeAge>
        let nameAliases: NameAliasesFile
        let cldr: CldrAnnotations

        var entries: [CatalogEntry] = []
        var ranges: [CodePointRange] = []
        /// Entry index of each variant's base, for the adjacency validation.
        var variantBase: [Int: Int] = [:]
        /// Count of emoji entries that took their name from CLDR.
        var cldrNamed = 0
        var emojiEmitted = 0

        func lookup(_ table: RangeTable<String>, _ codePoint: UInt32, what: String, line: Int) throws -> String {
            guard let value = table.value(for: codePoint) else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: line,
                                             reason: "no \(what) for U+\(String(codePoint, radix: 16, uppercase: true))")
            }
            return value
        }

        // MARK: (A) Emoji

        mutating func emitEmoji(fullyQualified rows: [EmojiTestRow]) throws {
            var baseRowByKey: [[UInt32]: Int] = [:]
            var problems: [String] = []
            for (index, row) in rows.enumerated() where !row.containsSkinTone {
                if baseRowByKey.updateValue(index, forKey: row.familyKey) != nil {
                    problems.append("emoji-test.txt:\(row.lineNumber): two bases share family key \(hexList(row.familyKey))")
                }
            }
            var variantRowsByBase: [Int: [Int]] = [:]
            for (index, row) in rows.enumerated() where row.containsSkinTone {
                if let base = baseRowByKey[row.familyKey]
                    ?? MultiPersonFamilies.baseByVariantKey[row.familyKey].flatMap({ baseRowByKey[$0] }) {
                    variantRowsByBase[base, default: []].append(index)
                } else {
                    problems.append("emoji-test.txt:\(row.lineNumber): toned sequence \(hexList(row.scalars)) has no base")
                }
            }
            guard problems.isEmpty else { throw CatalogError.invalid(problems) }

            for (index, row) in rows.enumerated() where !row.containsSkinTone {
                let baseIndex = entries.count
                appendEmoji(row, kind: .emoji)
                for variantIndex in variantRowsByBase[index] ?? [] {
                    variantBase[entries.count] = baseIndex
                    appendEmoji(rows[variantIndex], kind: .variant)
                }
            }
        }

        private mutating func appendEmoji(_ row: EmojiTestRow, kind: CatalogEntry.Kind) {
            let string = row.string
            var name = row.name.lowercased()
            var keywords: [String] = []
            var seen: Set<String> = []
            if let annotation = cldr.annotation(for: string) {
                if let tts = annotation.tts {
                    name = tts
                    cldrNamed += 1
                }
                for keyword in annotation.keywords where keyword != name && seen.insert(keyword).inserted {
                    keywords.append(keyword)
                }
            }
            if row.name != name && seen.insert(row.name).inserted {
                keywords.append(row.name)
            }
            entries.append(CatalogEntry(string: string, kind: kind, rank: 1,
                                        age: row.age, group: row.group,
                                        name: name, keywords: keywords))
            emojiEmitted += 1
        }

        // MARK: (B)+(C) Characters and ranges

        mutating func emitCharacters(rows: [UnicodeDataRow]) throws {
            var pendingFirst: (codePoint: UInt32, label: String, category: String, line: Int)?
            let emojiStrings = Set(entries.map { $0.string.exact })

            for row in rows {
                if let marker = row.rangeLabel {
                    try handleRangeMarker(marker, row: row, pendingFirst: &pendingFirst)
                    continue
                }
                let isSpace = CatalogBuilder.spaceFormats.contains(row.codePoint)
                guard CatalogBuilder.isListed(row.category) || isSpace else { continue }
                guard !CatalogBuilder.isEmojiComponent(row.codePoint) else { continue }
                guard let scalar = Unicode.Scalar(row.codePoint) else {
                    throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                                 reason: "code point is not a scalar")
                }
                let string = String(scalar)
                // A single-scalar emoji already emitted stays the only entry.
                guard !emojiStrings.contains(string.exact) else { continue }

                let kind = kind(for: row, isSpace: isSpace)
                let group = try lookup(blocks, row.codePoint, what: "block", line: row.lineNumber)
                let age = try lookupAge(row.codePoint, line: row.lineNumber)
                let script = try lookup(scripts, row.codePoint, what: "script", line: row.lineNumber)

                var name = row.name.lowercased()
                var usedCldr = false
                var keywords: [String] = []
                var seen: Set<String> = []
                let annotation = cldr.annotation(for: string)
                if let tts = annotation?.tts {
                    name = tts
                    usedCldr = true
                }
                for keyword in annotation?.keywords ?? [] where keyword != name && seen.insert(keyword).inserted {
                    keywords.append(keyword)
                }
                if row.name.lowercased() != name && seen.insert(row.name.lowercased()).inserted {
                    keywords.append(row.name.lowercased())
                }
                for alias in nameAliases.aliases[row.codePoint] ?? [] {
                    let lowered = alias.lowercased()
                    if lowered != name && seen.insert(lowered).inserted {
                        keywords.append(lowered)
                    }
                }
                if usedCldr { cldrNamed += 1 }

                let rank: UInt8
                if annotation != nil {
                    rank = 1
                } else if kind == .symbol || kind == .punctuation || kind == .space
                            || (kind == .number && script == "Common") {
                    rank = 2
                } else if CatalogBuilder.commonScripts.contains(script) {
                    rank = 3
                } else {
                    rank = 4
                }
                entries.append(CatalogEntry(string: string, kind: kind, rank: rank, age: age,
                                            group: group, name: name, keywords: keywords))
            }
            if let pendingFirst {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: pendingFirst.line,
                                             reason: "'\(pendingFirst.label), First' has no matching Last")
            }
        }

        private func kind(for row: UnicodeDataRow, isSpace: Bool) -> CatalogEntry.Kind {
            if isSpace { return .space }
            switch row.category.first {
            case "S": return .symbol
            case "P": return .punctuation
            case "L": return .letter
            case "N": return .number
            case "M": return .mark
            default: return .space
            }
        }

        private mutating func handleRangeMarker(
            _ marker: (label: String, isFirst: Bool), row: UnicodeDataRow,
            pendingFirst: inout (codePoint: UInt32, label: String, category: String, line: Int)?
        ) throws {
            if marker.isFirst {
                pendingFirst = (row.codePoint, marker.label, row.category, row.lineNumber)
                return
            }
            guard let first = pendingFirst else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                             reason: "'\(marker.label), Last' has no matching First")
            }
            pendingFirst = nil
            guard first.label == marker.label else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                             reason: "'\(marker.label), Last' follows '\(first.label), First'")
            }
            guard first.category == row.category else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                             reason: "range '\(marker.label)' mixes categories \(first.category) and \(row.category)")
            }
            let category = row.category
            if category == "Cs" || category == "Co" {
                return
            }
            guard category.hasPrefix("L") || category.hasPrefix("N") else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                             reason: "unexpected range category \(category) for '\(marker.label)'")
            }
            guard let rule = CatalogBuilder.rangeRules[marker.label] else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: row.lineNumber,
                                             reason: "no naming rule for range '\(marker.label)'")
            }
            ranges.append(CodePointRange(
                first: first.codePoint, last: row.codePoint, rule: rule,
                group: try lookup(blocks, first.codePoint, what: "block", line: row.lineNumber),
                age: try lookupAge(first.codePoint, line: row.lineNumber)))
        }

        private func lookupAge(_ codePoint: UInt32, line: Int) throws -> UnicodeAge {
            guard let age = ages.value(for: codePoint) else {
                throw CatalogError.malformed(file: "UnicodeData.txt", line: line,
                                             reason: "no derived age for U+\(String(codePoint, radix: 16, uppercase: true))")
            }
            return age
        }

        // MARK: (D) Extras

        mutating func emitExtras(_ extras: [ExtraRow]) throws {
            var existing = Set(entries.map { $0.string.exact })
            for extra in extras {
                var view = String.UnicodeScalarView()
                for scalar in extra.scalars {
                    guard let value = Unicode.Scalar(scalar) else {
                        throw CatalogError.malformed(file: "extras.tsv", line: extra.lineNumber,
                                                     reason: "invalid scalar \(String(scalar, radix: 16, uppercase: true))")
                    }
                    view.append(value)
                }
                let string = String(view)
                guard existing.insert(string.exact).inserted else {
                    throw CatalogError.malformed(file: "extras.tsv", line: extra.lineNumber,
                                                 reason: "'\(string.codePointDescription)' already exists in the catalogue")
                }
                entries.append(CatalogEntry(string: string, kind: extra.kind, rank: 2,
                                            age: UnicodeAge(major: 1, minor: 1), group: extra.group,
                                            name: extra.name, keywords: extra.keywords))
            }
        }

        // MARK: (E) Curated aliases

        mutating func applyAliases(_ aliases: [CuratedAlias]) throws {
            var indexByString: [ExactString: Int] = [:]
            for (index, entry) in entries.enumerated() where indexByString[entry.string.exact] == nil {
                indexByString[entry.string.exact] = index
            }

            var problems: [String] = []
            var seenAliases: Set<String> = []
            var attachments: [Int: [CatalogAlias]] = [:]
            for alias in aliases {
                let text = alias.text.lowercased()
                if !seenAliases.insert(text).inserted {
                    problems.append("aliases.tsv:\(alias.lineNumber): duplicate alias '\(text)'")
                }
                var seenItems: Set<ExactString> = []
                for (position, item) in alias.items.enumerated() {
                    if !seenItems.insert(item.exact).inserted {
                        problems.append("aliases.tsv:\(alias.lineNumber): alias '\(text)' repeats item '\(item.codePointDescription)'")
                    }
                    guard let index = indexByString[item.exact] else {
                        problems.append("aliases.tsv:\(alias.lineNumber): item '\(item.codePointDescription)' of alias '\(text)' matches no entry")
                        continue
                    }
                    attachments[index, default: []].append(CatalogAlias(text: text, rank: UInt8(min(position, 255))))
                }
            }
            guard problems.isEmpty else { throw CatalogError.invalid(problems) }

            for (index, aliasList) in attachments {
                let entry = entries[index]
                entries[index] = CatalogEntry(string: entry.string, kind: entry.kind, rank: 0,
                                              age: entry.age, group: entry.group, name: entry.name,
                                              keywords: entry.keywords, aliases: entry.aliases + aliasList)
            }
        }

        // MARK: (F) Validation

        func validate(expectedEmojiCount: Int) throws {
            var violations: [String] = []
            var seen: Set<ExactString> = []
            var currentEmoji = -1
            for (index, entry) in entries.enumerated() {
                if !seen.insert(entry.string.exact).inserted {
                    violations.append("duplicate entry string \(entry.string.codePointDescription)")
                }
                if entry.name.isEmpty || entry.name.contains("\t") || entry.name.contains("\n") {
                    violations.append("entry \(entry.string.codePointDescription) has an empty or unencodable name")
                }
                switch entry.kind {
                case .emoji:
                    currentEmoji = index
                case .variant:
                    if currentEmoji < 0 || variantBase[index] != currentEmoji {
                        violations.append("variant \(entry.string.codePointDescription) does not follow its base")
                    }
                default:
                    currentEmoji = -1
                }
                for scalar in entry.string.unicodeScalars where CatalogBuilder.isNoncharacter(scalar.value) {
                    violations.append("entry \(entry.string.codePointDescription) contains noncharacter U+\(String(scalar.value, radix: 16, uppercase: true))")
                }
            }
            if emojiEmitted != expectedEmojiCount {
                violations.append("emitted \(emojiEmitted) emoji but emoji-test.txt lists \(expectedEmojiCount) fully-qualified rows")
            }
            guard violations.isEmpty else { throw CatalogError.invalid(violations) }
        }

        // MARK: Statistics

        func statistics(contents: CatalogFormat.Contents, aliasCount: Int) throws -> CatalogStatistics {
            var byKind: [String: Int] = [:]
            var byRank: [String: Int] = [:]
            var longest: (length: Int, string: String) = (0, "")
            for entry in entries {
                byKind[entry.kind.rawValue, default: 0] += 1
                byRank[String(entry.rank), default: 0] += 1
                if entry.string.utf16.count > longest.length {
                    longest = (entry.string.utf16.count, entry.string)
                }
            }
            let rangeCodePoints = ranges.reduce(0) { $0 + Int($1.last - $1.first + 1) }
            return CatalogStatistics(
                unicodeVersion: contents.header.unicodeVersion,
                emojiVersion: contents.header.emojiVersion,
                cldrVersion: contents.header.cldrVersion,
                totalEntries: entries.count,
                entriesByKind: byKind,
                entriesByRank: byRank,
                rangeCount: ranges.count,
                rangeCodePoints: rangeCodePoints,
                emojiBases: byKind[CatalogEntry.Kind.emoji.rawValue] ?? 0,
                variants: byKind[CatalogEntry.Kind.variant.rawValue] ?? 0,
                maxUTF16Length: longest.length,
                longestEntry: longest.string,
                entriesWithCldrNames: cldrNamed,
                curatedAliases: aliasCount,
                entriesWithAliases: entries.filter { !$0.aliases.isEmpty }.count,
                outputBytes: try CatalogFormat.encode(contents).utf8.count)
        }
    }
}
