import XCTest
@testable import CharmsCatalogBuilder
import CharmsCore

final class EmojiTestParserTests: XCTestCase {
    private let text = """
        # emoji-test.txt
        # Version: 16.0

        # group: Smileys & Emotion

        # subgroup: face-smiling
        1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
        1F601                                                  ; minimally-qualified # 😁 E0.6 beaming face with smiling eyes

        # subgroup: hand-fingers-closed
        1F44D                                                  ; fully-qualified     # 👍 E0.6 thumbs up
        1F44D 1F3FB                                            ; fully-qualified     # 👍🏻 E1.0 thumbs up: light skin tone
        """

    func testRowsCarryGroupStatusAgeAndName() throws {
        let file = try EmojiTestParser.parse(text)
        XCTAssertEqual(file.version, "16.0")
        XCTAssertEqual(file.rows.count, 4)
        let thumbs = file.fullyQualified
        XCTAssertEqual(thumbs.count, 3)
        XCTAssertEqual(thumbs[1].scalars, [0x1F44D])
        XCTAssertEqual(thumbs[1].name, "thumbs up")
        XCTAssertEqual(thumbs[1].group, "Smileys & Emotion/hand-fingers-closed")
        XCTAssertEqual(thumbs[1].age, UnicodeAge(major: 0, minor: 6))
        XCTAssertEqual(thumbs[2].scalars, [0x1F44D, 0x1F3FB])
        XCTAssertTrue(thumbs[2].containsSkinTone)
        XCTAssertEqual(thumbs[2].familyKey, [0x1F44D])
        XCTAssertEqual(thumbs[2].lineNumber, 12)
    }

    func testMalformedRowsReportLineNumbers() {
        let cases: [String] = [
            "1F600 ; fully-qualified",
            "1F600 ; made-up-status        # 😀 E1.0 grinning face",
            "1F600 ; fully-qualified       # 😀 notaversion grinning face",
            "1F600 ; fully-qualified       # 😀",
            "; fully-qualified             # 😀 E1.0 grinning face",
            "1F600                         # 😀 E1.0 no status",
        ]
        for row in cases {
            let text = "# Version: 16.0\n# group: G\n# subgroup: S\n" + row + "\n"
            XCTAssertThrowsError(try EmojiTestParser.parse(text), row) { error in
                guard case .malformed(let file, let number, _) = error as? CatalogError else {
                    return XCTFail("expected malformed, got \(error)")
                }
                XCTAssertEqual(file, "emoji-test.txt")
                XCTAssertEqual(number, 4)
            }
        }
    }

    func testMissingVersionHeaderIsAnError() {
        XCTAssertThrowsError(try EmojiTestParser.parse("# group: G\n# subgroup: S\n1F600 ; fully-qualified # 😀 E1.0 grinning face\n"))
    }

    func testRowBeforeAnyGroupIsAnError() {
        XCTAssertThrowsError(try EmojiTestParser.parse("# Version: 16.0\n1F600 ; fully-qualified # 😀 E1.0 grinning face\n"))
    }
}

final class UnicodeDataParserTests: XCTestCase {
    func testParsesNameAndCategory() throws {
        let rows = try UnicodeDataFile.parse(
            "00A0;NO-BREAK SPACE;Zs;0;CS;<noBreak> 0020;;;;N;NON-BREAKING SPACE;;;;\n" +
            "3400;<CJK Ideograph Extension A, First>;Lo;0;L;;;;;N;;;;;\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].codePoint, 0x00A0)
        XCTAssertEqual(rows[0].name, "NO-BREAK SPACE")
        XCTAssertEqual(rows[0].category, "Zs")
        XCTAssertNil(rows[0].rangeLabel)
        XCTAssertEqual(rows[1].rangeLabel?.label, "CJK Ideograph Extension A")
        XCTAssertEqual(rows[1].rangeLabel?.isFirst, true)
    }

    func testFieldCountIsChecked() {
        XCTAssertThrowsError(try UnicodeDataFile.parse("0041;LATIN CAPITAL LETTER A;Lu\n")) { error in
            guard case .malformed(_, let line, _) = error as? CatalogError else {
                return XCTFail("expected malformed, got \(error)")
            }
            XCTAssertEqual(line, 1)
        }
    }
}

final class RangeTableParserTests: XCTestCase {
    func testLookupFindsContainingSpan() throws {
        let table: RangeTable<String> = try RangeTableParser.parse(
            "0041..005A    ; Latin # L&  [26] A..Z\n0061..007A ; Latin\n03B1 ; Greek\n", file: "t") { value, _ in
            String(value)
        }
        XCTAssertEqual(table.value(for: 0x41), "Latin")
        XCTAssertEqual(table.value(for: 0x5A), "Latin")
        XCTAssertEqual(table.value(for: 0x61), "Latin")
        XCTAssertEqual(table.value(for: 0x3B1), "Greek")
        XCTAssertNil(table.value(for: 0x5B))
    }

    func testSpansAreSortedForLookup() throws {
        // Scripts.txt groups rows by script, not by code point.
        let table: RangeTable<String> = try RangeTableParser.parse(
            "1000..10FF ; One\n0000..00FF ; Two\n", file: "t") { value, _ in
            String(value)
        }
        XCTAssertEqual(table.value(for: 0x41), "Two")
        XCTAssertEqual(table.value(for: 0x1040), "One")
    }

    func testMalformedRangeReportsLineNumber() {
        XCTAssertThrowsError(try RangeTableParser.parse("0041 ; A\nZZZZ ; B\n", file: "t") { v, _ in String(v) }) { error in
            guard case .malformed(let file, let line, _) = error as? CatalogError else {
                return XCTFail("expected malformed, got \(error)")
            }
            XCTAssertEqual(file, "t")
            XCTAssertEqual(line, 2)
        }
    }
}

final class BlocksParserTests: XCTestCase {
    func testVersionComesFromTheHeader() throws {
        let file = try BlocksParser.parse("# Blocks-18.0.0.txt\n# Date: x\n0000..007F; Basic Latin\n")
        XCTAssertEqual(file.unicodeVersion, "18.0.0")
        XCTAssertEqual(file.blocks.value(for: 0x41), "Basic Latin")
    }

    func testMissingHeaderIsAnError() {
        XCTAssertThrowsError(try BlocksParser.parse("0000..007F; Basic Latin\n"))
    }
}

final class NameAliasesFileTests: XCTestCase {
    func testOnlyWantedTypesAreKept() throws {
        let file = try NameAliasesFile.parse(
            "0000;NULL;control\n2126;OHM;correction\n212B;ANGSTROM UNIT;correction\n" +
            "00A0;NBSP;abbreviation\nFE0F;VS16;alternate\nFEFF;BYTE ORDER MARK;figment\n")
        XCTAssertNil(file.aliases[0x0000])
        XCTAssertEqual(file.aliases[0x2126], ["OHM"])
        XCTAssertEqual(file.aliases[0x212B], ["ANGSTROM UNIT"])
        XCTAssertEqual(file.aliases[0x00A0], ["NBSP"])
        XCTAssertEqual(file.aliases[0xFE0F], ["VS16"])
        XCTAssertNil(file.aliases[0xFEFF])
    }
}

final class CldrAnnotationsParserTests: XCTestCase {
    func testReadsKeywordsAndTts() throws {
        // JSON \uXXXX escapes keep the fixture scalars unambiguous: the keys
        // are U+2764 (no FE0F) and U+0023 U+20E3.
        let annotations = Data(#"{"annotations":{"identity":{"language":"en"},"annotations":{"❤":{"default":["emotion","heart"],"tts":["red heart"]},"x":{"tts":["plain x"]}}}}"#.utf8)
        let derived = Data(##"{"annotationsDerived":{"annotations":{"#⃣":{"default":["keycap"],"tts":["keycap: #"]}}}}"##.utf8)
        let cldr = try CldrAnnotationsParser.parse(annotations: annotations, annotationsFile: "a",
                                                   derived: derived, derivedFile: "d")
        XCTAssertEqual(cldr.annotation(for: "\u{2764}\u{FE0F}")?.tts, "red heart")
        XCTAssertEqual(cldr.annotation(for: "\u{2764}\u{FE0F}")?.keywords, ["emotion", "heart"])
        XCTAssertEqual(cldr.annotation(for: "\u{0023}\u{FE0F}\u{20E3}")?.tts, "keycap: #")
        XCTAssertEqual(cldr.annotation(for: "x")?.keywords, [])
        XCTAssertEqual(cldr.annotation(for: "x")?.tts, "plain x")
        XCTAssertNil(cldr.annotation(for: "missing"))
    }

    func testBaseFileWinsOverDerived() throws {
        let annotations = Data(#"{"annotations":{"annotations":{"a":{"tts":["from base"]}}}}"#.utf8)
        let derived = Data(#"{"annotationsDerived":{"annotations":{"a":{"tts":["from derived"]},"b":{"tts":["only derived"]}}}}"#.utf8)
        let cldr = try CldrAnnotationsParser.parse(annotations: annotations, annotationsFile: "a",
                                                   derived: derived, derivedFile: "d")
        XCTAssertEqual(cldr.annotation(for: "a")?.tts, "from base")
        XCTAssertEqual(cldr.annotation(for: "b")?.tts, "only derived")
    }

    func testMissingRootKeyIsAnError() {
        let bad = Data(#"{"wrongRoot":{"annotations":{}}}"#.utf8)
        XCTAssertThrowsError(try CldrAnnotationsParser.parse(annotations: bad, annotationsFile: "a",
                                                           derived: bad, derivedFile: "d")) { error in
            guard case .invalidStructure = error as? CatalogError else {
                return XCTFail("expected invalidStructure, got \(error)")
            }
        }
    }
}

final class CuratedFilesTests: XCTestCase {
    func testAliasItemsInUPlusNotation() throws {
        let aliases = try CuratedFiles.parseAliases("heart\tU+2764+U+FE0F ♥\ncmd\t⌘\n")
        XCTAssertEqual(aliases.count, 2)
        XCTAssertEqual(aliases[0].text, "heart")
        XCTAssertEqual(aliases[0].items, ["\u{2764}\u{FE0F}", "\u{2665}"])
        XCTAssertEqual(aliases[0].lineNumber, 1)
        XCTAssertEqual(aliases[1].items, ["\u{2318}"])
    }

    func testMalformedUPlusItemIsAnError() {
        for bad in ["U+", "U+ZZZZ", "U+2764+", "x\tU+123456789"] {
            XCTAssertThrowsError(try CuratedFiles.parseAliases("a\t\(bad)\n"), bad) { error in
                guard case .malformed(_, let line, _) = error as? CatalogError else {
                    return XCTFail("expected malformed, got \(error)")
                }
                XCTAssertEqual(line, 1)
            }
        }
    }

    func testExtrasRow() throws {
        let extras = try CuratedFiles.parseExtras("F8FF\ts\tPrivate Use Area\tapple logo\tapple|mac\n")
        XCTAssertEqual(extras.count, 1)
        XCTAssertEqual(extras[0].scalars, [0xF8FF])
        XCTAssertEqual(extras[0].kind, .symbol)
        XCTAssertEqual(extras[0].group, "Private Use Area")
        XCTAssertEqual(extras[0].name, "apple logo")
        XCTAssertEqual(extras[0].keywords, ["apple", "mac"])
    }

    func testExtrasRejectsUnknownKind() {
        XCTAssertThrowsError(try CuratedFiles.parseExtras("F8FF\tq\tG\tn\tk\n")) { error in
            guard case .malformed = error as? CatalogError else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }
}
