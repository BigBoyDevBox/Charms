import XCTest
@testable import CharmsCatalogBuilder
import CharmsCore

/// Builder tests over small inline fixtures. Each test assembles a
/// `CatalogSources` with just the fields it exercises; the rest are empty but
/// valid.
final class BuilderTests: XCTestCase {
    private func sources(
        unicodeData: String = "",
        nameAliases: String = "",
        blocks: String = "# Blocks-18.0.0.txt\n# Date: t\n0000..FFFF; Plane Zero\n10000..10FFFF; Planes\n",
        scripts: String = "0000..10FFFF ; Common # x\n",
        derivedAge: String = "0000..10FFFF ; 1.1 # x\n",
        emojiTest: String = "# emoji-test.txt\n# Version: 16.0\n",
        annotations: String = #"{"annotations":{"annotations":{}}}"#,
        annotationsDerived: String = #"{"annotationsDerived":{"annotations":{}}}"#,
        aliases: String = "",
        extras: String = ""
    ) -> CatalogSources {
        CatalogSources(
            unicodeData: unicodeData, nameAliases: nameAliases, blocks: blocks,
            scripts: scripts, derivedAge: derivedAge, emojiTest: emojiTest,
            annotations: Data(annotations.utf8), annotationsDerived: Data(annotationsDerived.utf8),
            aliases: aliases, extras: extras)
    }

    private func emojiRows(_ rows: String) -> String {
        "# emoji-test.txt\n# Version: 16.0\n# group: G\n# subgroup: S\n" + rows
    }

    private func row(_ scalars: String, _ name: String) -> String {
        "\(scalars.padding(toLength: 50, withPad: " ", startingAt: 0)) ; fully-qualified     # X E1.0 \(name)\n"
    }

    // MARK: - Emoji assembly

    func testVariantBeforeBaseStillFollowsIt() throws {
        let result = try CatalogBuilder.build(sources(emojiTest: emojiRows(
            row("1F44D 1F3FB", "thumbs up: light skin tone") +
            row("1F44D", "thumbs up"))))
        XCTAssertEqual(result.contents.entries.map(\.string), ["\u{1F44D}", "\u{1F44D}\u{1F3FB}"])
        XCTAssertEqual(result.contents.entries.map(\.kind), [.emoji, .variant])
    }

    func testNonContiguousVariantsJoinTheirBase() throws {
        // Two unrelated bases with one's variant interleaved: file order
        // decides base positions, variants still join their own base.
        let result = try CatalogBuilder.build(sources(emojiTest: emojiRows(
            row("1F600", "grinning face") +
            row("1F44D", "thumbs up") +
            row("1F600 1F3FB", "grinning face: light skin tone"))))
        XCTAssertEqual(result.contents.entries.map(\.string),
                       ["\u{1F600}", "\u{1F600}\u{1F3FB}", "\u{1F44D}"])
        XCTAssertEqual(result.contents.entries.map(\.kind), [.emoji, .variant, .emoji])
    }

    func testMultiPersonTonedSequencesJoinTheFamilyBase() throws {
        // The tone-free 1FAF1 200D 1FAF2 handshake is not a fully-qualified
        // row, so these mixed-tone forms attach to 1F91D via the family table.
        let result = try CatalogBuilder.build(sources(emojiTest: emojiRows(
            row("1F91D", "handshake") +
            row("1F91D 1F3FB", "handshake: light skin tone") +
            row("1FAF1 1F3FB 200D 1FAF2 1F3FC", "handshake: light skin tone, medium-light skin tone"))))
        XCTAssertEqual(result.contents.entries.map(\.string),
                       ["\u{1F91D}", "\u{1F91D}\u{1F3FB}", "\u{1FAF1}\u{1F3FB}\u{200D}\u{1FAF2}\u{1F3FC}"])
        XCTAssertEqual(result.contents.entries.map(\.kind), [.emoji, .variant, .variant])
    }

    func testVariantWithoutBaseIsAnError() {
        XCTAssertThrowsError(try CatalogBuilder.build(sources(emojiTest: emojiRows(
            row("1F600 1F3FB", "grinning face: light skin tone"))))) { error in
            guard case .invalid(let problems) = error as? CatalogError else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertTrue(problems.contains { $0.contains("has no base") })
        }
    }

    func testEmojiTtsAndKeywordsComeFromCldrWithFE0FStripped() throws {
        // The CLDR key is U+2764 without FE0F; the entry keeps the full
        // fully-qualified sequence.
        let annotations = #"{"annotations":{"annotations":{"❤":{"default":["emotion","red"],"tts":["red heart"]}}}}"#
        let result = try CatalogBuilder.build(sources(
            emojiTest: emojiRows(row("2764 FE0F", "heavy black heart")),
            annotations: annotations))
        let entry = result.contents.entries[0]
        XCTAssertEqual(entry.string, "\u{2764}\u{FE0F}")
        XCTAssertEqual(entry.name, "red heart")
        XCTAssertEqual(entry.keywords, ["emotion", "red", "heavy black heart"])
        XCTAssertEqual(result.statistics.entriesWithCldrNames, 1)
    }

    func testEmojiNameFallsBackToEmojiTestName() throws {
        let result = try CatalogBuilder.build(sources(emojiTest: emojiRows(
            row("1F600", "grinning face"))))
        XCTAssertEqual(result.contents.entries[0].name, "grinning face")
        XCTAssertEqual(result.contents.entries[0].keywords, [])
        XCTAssertEqual(result.contents.entries[0].rank, 1)
        XCTAssertEqual(result.contents.entries[0].group, "G/S")
    }

    // MARK: - Characters

    func testCharacterKindsGroupsAndRanks() throws {
        let result = try CatalogBuilder.build(sources(
            unicodeData: "0030;DIGIT ZERO;Nd;0;EN;;0;0;0;N;;;;;\n"
                + "0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;;\n"
                + "2192;RIGHTWARDS ARROW;Sm;0;ON;;;;;N;;;;;\n"
                + "10000;FANCY LETTER;Lo;0;L;;;;;N;;;;;\n",
            scripts: "0030 ; Common # x\n0041 ; Latin # x\n2192 ; Common # x\n10000 ; Vai # x\n"))
        let entries = result.contents.entries
        XCTAssertEqual(entries.map { Array($0.string.unicodeScalars.map(\.value)) },
                       [[0x30], [0x41], [0x2192], [0x10000]])
        XCTAssertEqual(entries.map(\.kind), [.number, .letter, .symbol, .letter])
        XCTAssertEqual(entries.map(\.rank), [2, 3, 2, 4])
        XCTAssertEqual(entries.map(\.name),
                       ["digit zero", "latin capital letter a", "rightwards arrow", "fancy letter"])
        XCTAssertEqual(entries[2].group, "Plane Zero")
        XCTAssertEqual(entries[3].group, "Planes")
    }

    func testFormatCharactersAreSpacesAndComponentsExcluded() throws {
        let result = try CatalogBuilder.build(sources(
            unicodeData: "0001;<control>;Cc;0;BN;;;;;N;START OF HEADING;;;;\n"
                + "00AD;SOFT HYPHEN;Cf;0;BN;;;;;N;;;;;\n"
                + "200D;ZERO WIDTH JOINER;Cf;0;BN;;;;;N;;;;;\n"
                + "E000;<Private Use, First>;Co;0;L;;;;;N;;;;;\n"
                + "F8FF;<Private Use, Last>;Co;0;L;;;;;N;;;;;\n"
                + "1F3FB;EMOJI MODIFIER FITZPATRICK TYPE-1-2;Sk;0;ON;;;;;N;;;;;\n"
                + "1F1E6;REGIONAL INDICATOR SYMBOL LETTER A;So;0;L;;;;;N;;;;;\n"))
        XCTAssertEqual(result.contents.entries.map(\.string), ["\u{AD}", "\u{200D}"])
        XCTAssertEqual(result.contents.entries.map(\.kind), [.space, .space])
        XCTAssertTrue(result.contents.ranges.isEmpty)
    }

    func testCharacterKeywordsAndCldrName() throws {
        let annotations = #"{"annotations":{"annotations":{"→":{"default":["arrow","right"],"tts":["right-pointing arrow"]}}}}"#
        let result = try CatalogBuilder.build(sources(
            unicodeData: "2192;RIGHTWARDS ARROW;Sm;0;ON;;;;;N;;;;;\n00AD;SOFT HYPHEN;Cf;0;BN;;;;;N;;;;;\n",
            nameAliases: "2192;RIGHT ARROW;correction\n00AD;SHY;abbreviation\n",
            annotations: annotations))
        let arrow = result.contents.entries[0]
        XCTAssertEqual(arrow.name, "right-pointing arrow")
        XCTAssertEqual(arrow.keywords, ["arrow", "right", "rightwards arrow", "right arrow"])
        XCTAssertEqual(arrow.rank, 1)
        let shy = result.contents.entries[1]
        XCTAssertEqual(shy.name, "soft hyphen")
        XCTAssertEqual(shy.keywords, ["shy"])
        XCTAssertEqual(shy.rank, 2)
    }

    func testSingleScalarEmojiWinsOverTheCharacter() throws {
        let result = try CatalogBuilder.build(sources(
            unicodeData: "1F600;GRINNING FACE;So;0;ON;;;;;N;;;;;\n2764;HEAVY BLACK HEART;So;0;ON;;;;;N;;;;;\n",
            emojiTest: emojiRows(row("1F600", "grinning face") + row("2764 FE0F", "red heart"))))
        // U+1F600 is the emoji; U+2764 needs FE0F so it stays a text entry.
        XCTAssertEqual(result.contents.entries.map(\.string),
                       ["\u{1F600}", "\u{2764}\u{FE0F}", "\u{2764}"])
    }

    // MARK: - Ranges

    func testRangesAndUnknownLabels() throws {
        let result = try CatalogBuilder.build(sources(
            unicodeData: "4E00;<CJK Ideograph, First>;Lo;0;L;;;;;N;;;;;\n"
                + "9FFF;<CJK Ideograph, Last>;Lo;0;L;;;;;N;;;;;\n"
                + "AC00;<Hangul Syllable, First>;Lo;0;L;;;;;N;;;;;\n"
                + "D7A3;<Hangul Syllable, Last>;Lo;0;L;;;;;N;;;;;\n"
                + "D800;<Non Private Use High Surrogate, First>;Cs;0;L;;;;;N;;;;;\n"
                + "DB7F;<Non Private Use High Surrogate, Last>;Cs;0;L;;;;;N;;;;;\n"))
        XCTAssertTrue(result.contents.entries.isEmpty)
        XCTAssertEqual(result.contents.ranges.count, 2)
        XCTAssertEqual(result.contents.ranges[0],
                       CodePointRange(first: 0x4E00, last: 0x9FFF,
                                      rule: .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"),
                                      group: "Plane Zero", age: UnicodeAge(major: 1, minor: 1)))
        XCTAssertEqual(result.contents.ranges[1].rule, .hangulSyllable)
    }

    func testUnknownRangeLabelIsAnError() {
        XCTAssertThrowsError(try CatalogBuilder.build(sources(
            unicodeData: "1000;<Future Block, First>;Lo;0;L;;;;;N;;;;;\n"
                + "10FF;<Future Block, Last>;Lo;0;L;;;;;N;;;;;\n"))) { error in
            guard case .malformed(let file, _, let reason) = error as? CatalogError else {
                return XCTFail("expected malformed, got \(error)")
            }
            XCTAssertEqual(file, "UnicodeData.txt")
            XCTAssertTrue(reason.contains("Future Block"))
        }
    }

    // MARK: - Extras and aliases

    func testExtrasAreAppendedWithRankTwo() throws {
        let result = try CatalogBuilder.build(sources(
            extras: "F8FF\ts\tPrivate Use Area\tapple logo\tapple|mac\n"))
        let entry = result.contents.entries[0]
        XCTAssertEqual(entry.string, "\u{F8FF}")
        XCTAssertEqual(entry.kind, .symbol)
        XCTAssertEqual(entry.rank, 2)
        XCTAssertEqual(entry.name, "apple logo")
        XCTAssertEqual(entry.keywords, ["apple", "mac"])
        XCTAssertEqual(entry.age, UnicodeAge(major: 1, minor: 1))
    }

    func testExtraDuplicatingAnEntryIsAnError() {
        XCTAssertThrowsError(try CatalogBuilder.build(sources(
            unicodeData: "00AD;SOFT HYPHEN;Cf;0;BN;;;;;N;;;;;\n",
            extras: "00AD\ts\tX\tdupe\t\n"))) { error in
            guard case .malformed(let file, _, _) = error as? CatalogError else {
                return XCTFail("expected malformed, got \(error)")
            }
            XCTAssertEqual(file, "extras.tsv")
        }
    }

    func testAliasUPlusItemAttachesToOhmSignNotOmega() throws {
        // U+2126 and U+03A9 are canonically equal but different entries.
        let result = try CatalogBuilder.build(sources(
            unicodeData: "03A9;GREEK CAPITAL LETTER OMEGA;Lu;0;L;;;;;N;;;;03C9;\n"
                + "2126;OHM SIGN;Lu;0;L;03A9;;;;N;OHM;;;03C9;\n",
            aliases: "ohm\tU+2126\n"))
        let omega = result.contents.entries[0]
        let ohm = result.contents.entries[1]
        XCTAssertEqual(Array(omega.string.unicodeScalars.map(\.value)), [0x03A9])
        XCTAssertEqual(Array(ohm.string.unicodeScalars.map(\.value)), [0x2126])
        XCTAssertEqual(ohm.aliases, [CatalogAlias(text: "ohm", rank: 0)])
        XCTAssertEqual(ohm.rank, 0)
        XCTAssertEqual(omega.aliases, [])
        XCTAssertNotEqual(omega.rank, 0)
    }

    func testAliasRanksFollowItemPosition() throws {
        let result = try CatalogBuilder.build(sources(
            unicodeData: "2190;LEFTWARDS ARROW;Sm;0;ON;;;;;N;;;;;\n2192;RIGHTWARDS ARROW;Sm;0;ON;;;;;N;;;;;\n",
            aliases: "arrow\t→ U+2190\n"))
        XCTAssertEqual(result.contents.entries[0].aliases, [CatalogAlias(text: "arrow", rank: 1)])
        XCTAssertEqual(result.contents.entries[1].aliases, [CatalogAlias(text: "arrow", rank: 0)])
    }

    func testAliasProblemsAreListedTogether() {
        XCTAssertThrowsError(try CatalogBuilder.build(sources(
            unicodeData: "2192;RIGHTWARDS ARROW;Sm;0;ON;;;;;N;;;;;\n",
            aliases: "dup\t→\ndup\t→\nunknown\tU+9999\nrepeats\t→ →\n"))) { error in
            guard case .invalid(let problems) = error as? CatalogError else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertTrue(problems.contains { $0.contains("duplicate alias 'dup'") })
            XCTAssertTrue(problems.contains { $0.contains("'unknown'") && $0.contains("matches no entry") })
            XCTAssertTrue(problems.contains { $0.contains("'repeats'") && $0.contains("repeats item") })
        }
    }
}
