import XCTest
@testable import CharmsCore

final class CatalogFormatTests: XCTestCase {
    private let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")

    private func age(_ text: String) -> UnicodeAge { UnicodeAge(text)! }

    private func sample() -> CatalogFormat.Contents {
        CatalogFormat.Contents(
            header: header,
            entries: [
                CatalogEntry(string: "\u{2192}", kind: .symbol, rank: 0, age: age("1.1"), group: "Arrows", name: "right arrow",
                             keywords: ["rightwards arrow", "east"],
                             aliases: [CatalogAlias(text: "->", rank: 0), CatalogAlias(text: "arrow", rank: 2)]),
                CatalogEntry(string: "\u{1F44D}", kind: .emoji, rank: 1, age: age("0.6"), group: "People & Body/hand-fingers-closed", name: "thumbs up",
                             keywords: ["+1", "hand", "thumb"]),
                CatalogEntry(string: "\u{1F44D}\u{1F3FB}", kind: .variant, rank: 1, age: age("1.0"), group: "People & Body/hand-fingers-closed", name: "thumbs up: light skin tone"),
                CatalogEntry(string: "\u{1F44D}\u{1F3FD}", kind: .variant, rank: 1, age: age("1.0"), group: "People & Body/hand-fingers-closed", name: "thumbs up: medium skin tone"),
                CatalogEntry(string: "\u{7C}", kind: .symbol, rank: 2, age: age("1.1"), group: "Basic Latin", name: "vertical line",
                             keywords: ["a|b", "back\\slash"],
                             aliases: [CatalogAlias(text: "|", rank: 0), CatalogAlias(text: "#pipe", rank: 3)])
            ],
            ranges: [
                CodePointRange(first: 0x4E00, last: 0x9FFF, rule: .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"), group: "CJK Unified Ideographs", age: age("1.1")),
                CodePointRange(first: 0xAC00, last: 0xD7A3, rule: .hangulSyllable, group: "Hangul Syllables", age: age("2.0"))
            ]
        )
    }

    func testRoundTripPreservesEveryField() throws {
        let contents = sample()
        let text = try CatalogFormat.encode(contents)
        let decoded = try CatalogFormat.decode(Data(text.utf8))
        XCTAssertEqual(decoded, contents)
    }

    func testEncodingIsDeterministic() throws {
        XCTAssertEqual(try CatalogFormat.encode(sample()), try CatalogFormat.encode(sample()))
    }

    func testEntryLineLayout() throws {
        let text = try CatalogFormat.encode(sample())
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("2192\ts\t0\t1.1\tArrows\tright arrow\trightwards arrow|east\t->|arrow#2"))
        XCTAssertTrue(lines.contains("1F44D 1F3FB\tv\t1\t1.0\tPeople & Body/hand-fingers-closed\tthumbs up: light skin tone\t\t"))
        XCTAssertTrue(lines.contains("@\t4E00\t9FFF\thex\tCJK UNIFIED IDEOGRAPH-\tCJK Unified Ideographs\t1.1"))
        XCTAssertTrue(lines.contains("@\tAC00\tD7A3\thangul\t\tHangul Syllables\t2.0"))
    }

    func testPipeHashAndBackslashSurviveEscaping() throws {
        let decoded = try CatalogFormat.decode(Data(try CatalogFormat.encode(sample()).utf8))
        let pipe = decoded.entries[4]
        XCTAssertEqual(pipe.keywords, ["a|b", "back\\slash"])
        XCTAssertEqual(pipe.aliases, [CatalogAlias(text: "|", rank: 0), CatalogAlias(text: "#pipe", rank: 3)])
    }

    func testTabInFieldIsRejected() {
        var contents = sample()
        contents.entries[0] = CatalogEntry(string: "x", kind: .letter, rank: 3, age: age("1.1"), group: "Basic Latin", name: "bad\tname")
        XCTAssertThrowsError(try CatalogFormat.encode(contents))
    }

    func testUnsupportedVersionIsRejected() {
        let text = "!format\t99\n!unicode\t18.0.0\n!emoji\t18.0\n!cldr\t49\n"
        XCTAssertThrowsError(try CatalogFormat.decode(Data(text.utf8))) { error in
            XCTAssertEqual(error as? CatalogFormat.FormatError, .unsupportedVersion(99))
        }
    }

    func testMalformedLinesReportTheirLineNumber() {
        let text = "!format\t1\n!unicode\t18.0.0\n!emoji\t18.0\n!cldr\t49\n2192\ts\t0\n"
        XCTAssertThrowsError(try CatalogFormat.decode(Data(text.utf8))) { error in
            guard case .malformedLine(let number, _)? = error as? CatalogFormat.FormatError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(number, 5)
        }
    }

    func testSurrogateAndOutOfRangeScalarsAreRejected() {
        for scalars in ["D800", "110000", "", "21 92Z"] {
            let text = "!format\t1\n!unicode\t18.0.0\n!emoji\t18.0\n!cldr\t49\n\(scalars)\ts\t0\t1.1\tg\tn\t\t\n"
            if scalars.isEmpty {
                // A line that starts with a tab is still an entry line and must fail.
                XCTAssertThrowsError(try CatalogFormat.decode(Data(text.utf8)), "scalars: '\(scalars)'")
            } else {
                XCTAssertThrowsError(try CatalogFormat.decode(Data(text.utf8)), "scalars: '\(scalars)'")
            }
        }
    }
}

final class CatalogTests: XCTestCase {
    private func age(_ text: String) -> UnicodeAge { UnicodeAge(text)! }

    private func makeCatalog() -> Catalog {
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        let entries = [
            CatalogEntry(string: "\u{C5}", kind: .letter, rank: 3, age: age("1.1"), group: "Latin-1 Supplement", name: "latin capital letter a with ring above"),
            CatalogEntry(string: "\u{212B}", kind: .symbol, rank: 2, age: age("1.1"), group: "Letterlike Symbols", name: "angstrom sign"),
            CatalogEntry(string: "\u{1F44B}", kind: .emoji, rank: 1, age: age("0.6"), group: "People & Body/hand-fingers-open", name: "waving hand"),
            CatalogEntry(string: "\u{1F44B}\u{1F3FB}", kind: .variant, rank: 1, age: age("1.0"), group: "People & Body/hand-fingers-open", name: "waving hand: light skin tone"),
            CatalogEntry(string: "\u{1F44B}\u{1F3FD}", kind: .variant, rank: 1, age: age("1.0"), group: "People & Body/hand-fingers-open", name: "waving hand: medium skin tone"),
            CatalogEntry(string: "\u{1F91D}", kind: .emoji, rank: 1, age: age("3.0"), group: "People & Body/hands", name: "handshake"),
            CatalogEntry(string: "\u{1FAF1}\u{1F3FB}\u{200D}\u{1FAF2}\u{1F3FD}", kind: .variant, rank: 1, age: age("14.0"), group: "People & Body/hands", name: "handshake: light skin tone, medium skin tone"),
            CatalogEntry(string: "\u{1F91D}\u{1F3FD}", kind: .variant, rank: 1, age: age("14.0"), group: "People & Body/hands", name: "handshake: medium skin tone"),
            CatalogEntry(string: "\u{1F600}", kind: .emoji, rank: 1, age: age("1.0"), group: "Smileys & Emotion/face-smiling", name: "grinning face")
        ]
        let ranges = [
            CodePointRange(first: 0xAC00, last: 0xD7A3, rule: .hangulSyllable, group: "Hangul Syllables", age: age("2.0")),
            CodePointRange(first: 0x4E00, last: 0x9FFF, rule: .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"), group: "CJK Unified Ideographs", age: age("1.1"))
        ]
        return Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: ranges))
    }

    func testCanonicallyEquivalentCharactersStayDistinct() {
        let catalog = makeCatalog()
        // Swift's String equality treats these as equal; the catalogue must not.
        XCTAssertEqual("\u{C5}", "\u{212B}")
        XCTAssertEqual(catalog.index(of: "\u{C5}"), 0)
        XCTAssertEqual(catalog.index(of: "\u{212B}"), 1)
        XCTAssertEqual(catalog.resolve("\u{212B}")?.name, "angstrom sign")
        // The decomposed form is not an entry at all.
        XCTAssertNil(catalog.index(of: "A\u{30A}"))
    }

    func testVariantsBelongToThePrecedingEmoji() {
        let catalog = makeCatalog()
        XCTAssertEqual(catalog.variants(ofEntryAt: 2), 3..<5)
        XCTAssertEqual(catalog.variants(ofEntryAt: 5), 6..<8)
        XCTAssertNil(catalog.variants(ofEntryAt: 8))
        XCTAssertEqual(catalog.base(ofVariantAt: 4), 2)
        XCTAssertEqual(catalog.base(ofVariantAt: 7), 5)
        XCTAssertNil(catalog.base(ofVariantAt: 2))
    }

    func testPreferredToneUsesOnlyDefinedUniformVariants() {
        let catalog = makeCatalog()
        XCTAssertEqual(catalog.preferredIndex(for: 2, tone: .medium), 4)
        XCTAssertEqual(catalog.preferredIndex(for: 2, tone: .none), 2)
        // No dark variant is listed, so nothing is manufactured.
        XCTAssertEqual(catalog.preferredIndex(for: 2, tone: .dark), 2)
        // The mixed-tone handshake does not satisfy a uniform preference.
        XCTAssertEqual(catalog.preferredIndex(for: 5, tone: .medium), 7)
        XCTAssertEqual(catalog.preferredIndex(for: 5, tone: .light), 5)
        // An emoji without variants is unchanged.
        XCTAssertEqual(catalog.preferredIndex(for: 8, tone: .medium), 8)
    }

    func testRangeCharactersResolveWithAlgorithmicNames() {
        let catalog = makeCatalog()
        XCTAssertEqual(catalog.resolve("\u{4E2D}")?.name, "cjk unified ideograph-4e2d")
        XCTAssertEqual(catalog.resolve("\u{D55C}")?.name, "hangul syllable han")
        XCTAssertEqual(catalog.resolve("\u{AC00}")?.name, "hangul syllable ga")
        XCTAssertEqual(catalog.resolve("\u{D7A3}")?.name, "hangul syllable hih")
        XCTAssertNil(catalog.resolve("\u{3400}"))
        XCTAssertNil(catalog.resolve("\u{4E2D}\u{4E2D}"))
    }

    func testCodePointDescription() {
        XCTAssertEqual("\u{2192}".codePointDescription, "U+2192")
        XCTAssertEqual("\u{1F469}\u{200D}\u{1F4BB}".codePointDescription, "U+1F469 U+200D U+1F4BB")
        XCTAssertEqual("x".codePointDescription, "U+0078")
    }

    func testDisplayNameCapitalisesFirstLetterOnly() {
        let entry = CatalogEntry(string: "\u{2192}", kind: .symbol, rank: 0, age: age("1.1"), group: "Arrows", name: "right arrow")
        XCTAssertEqual(entry.displayName, "Right arrow")
    }
}
