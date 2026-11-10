import XCTest
@testable import CharmsCore

/// A hand-built catalogue shaped like the real one: emoji first, then
/// characters, each with the kind of names, keywords and aliases the
/// generator produces. Every expectation below was worked out from the
/// ranking rules, not copied from the engine's output.
final class SearchIndexTests: XCTestCase {
    private static let grin = "\u{1F600}"
    private static let thumbsUp = "\u{1F44D}"
    private static let thumbsUpMedium = "\u{1F44D}\u{1F3FD}"
    private static let hundred = "\u{1F4AF}"
    private static let redHeart = "\u{2764}\u{FE0F}"
    private static let bow = "\u{1F3F9}"
    private static let rightArrowEmoji = "\u{27A1}\u{FE0F}"
    private static let fire = "\u{1F525}"
    private static let fireEngine = "\u{1F692}"
    private static let times = "\u{D7}"
    private static let letterX = "x"
    private static let aMacron = "\u{100}"
    private static let leftArrow = "\u{2190}"
    private static let rightArrow = "\u{2192}"
    private static let upRightArrow = "\u{2197}"
    private static let strokeArrow = "\u{219B}"
    private static let notEqual = "\u{2260}"
    private static let infinity = "\u{221E}"
    private static let command = "\u{2318}"
    private static let check = "\u{2713}"
    private static let textHeart = "\u{2764}"
    private static let ideographFace = "\u{FACE}"
    private static let eAcute = "\u{E9}"
    private static let plus = "+"
    private static let numberSign = "#"
    private static let noBreakSpace = "\u{A0}"
    private static let ohm = "\u{2126}"
    private static let omega = "\u{3A9}"

    private static func age(_ text: String) -> UnicodeAge { UnicodeAge(text)! }

    private static func emoji(_ string: String, _ name: String, _ keywords: [String], group: String, aliases: [CatalogAlias] = [], kind: CatalogEntry.Kind = .emoji) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: 1, age: age("1.0"), group: group, name: name, keywords: keywords, aliases: aliases)
    }

    private static func character(_ string: String, _ name: String, kind: CatalogEntry.Kind = .symbol, rank: UInt8, group: String, keywords: [String] = [], aliases: [CatalogAlias] = []) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: aliases.isEmpty ? rank : 0, age: age("1.1"), group: group, name: name, keywords: keywords, aliases: aliases)
    }

    private static func alias(_ text: String, _ rank: UInt8 = 0) -> CatalogAlias { CatalogAlias(text: text, rank: rank) }

    private static let index: SearchIndex = {
        let entries: [CatalogEntry] = [
            emoji(grin, "grinning face", ["face", "grin", "happy", "smile"], group: "Smileys & Emotion/face-smiling"),
            emoji(thumbsUp, "thumbs up", ["+1", "hand", "thumb", "up"], group: "People & Body/hand-fingers-closed"),
            emoji(thumbsUpMedium, "thumbs up: medium skin tone", ["+1", "hand", "medium skin tone", "thumb", "up"], group: "People & Body/hand-fingers-closed", kind: .variant),
            emoji(hundred, "hundred points", ["100", "full", "hundred", "score"], group: "Smileys & Emotion/emotion"),
            emoji(redHeart, "red heart", ["heart", "love"], group: "Smileys & Emotion/heart", aliases: [alias("heart")]),
            emoji(bow, "bow and arrow", ["archer", "arrow", "bow"], group: "Objects/tool"),
            emoji(rightArrowEmoji, "right arrow", ["arrow", "direction", "east", "right"], group: "Symbols/arrow"),
            emoji(fire, "fire", ["flame", "hot"], group: "Travel & Places/sky & weather"),
            emoji(fireEngine, "fire engine", ["engine", "fire", "truck"], group: "Travel & Places/transport-ground"),
            character(times, "multiplication sign", rank: 1, group: "Latin-1 Supplement", keywords: ["multiply", "times"], aliases: [alias("x"), alias("times")]),
            character(letterX, "latin small letter x", kind: .letter, rank: 3, group: "Basic Latin"),
            character(aMacron, "latin capital letter a with macron", kind: .letter, rank: 3, group: "Latin Extended-A"),
            character(leftArrow, "left arrow", rank: 1, group: "Arrows", keywords: ["arrow", "left", "leftwards arrow"], aliases: [alias("arrow", 1), alias("<-")]),
            character(rightArrow, "right arrow", rank: 1, group: "Arrows", keywords: ["arrow", "right", "rightwards arrow"], aliases: [alias("arrow"), alias("->"), alias("right")]),
            character(upRightArrow, "up-right arrow", rank: 1, group: "Arrows", keywords: ["arrow", "direction", "north east arrow", "northeast"]),
            character(strokeArrow, "rightwards arrow with stroke", rank: 2, group: "Arrows"),
            character(notEqual, "not equal", rank: 1, group: "Mathematical Operators", keywords: ["inequality", "not equal to"], aliases: [alias("!="), alias("neq")]),
            character(infinity, "infinity", rank: 1, group: "Mathematical Operators", aliases: [alias("inf"), alias("infinity")]),
            character(command, "place of interest sign", rank: 2, group: "Miscellaneous Technical", keywords: ["command key"], aliases: [alias("cmd"), alias("command")]),
            character(check, "check mark", rank: 2, group: "Dingbats", aliases: [alias("check"), alias("tick")]),
            character(textHeart, "heavy black heart", rank: 2, group: "Dingbats"),
            character(ideographFace, "cjk compatibility ideograph-face", kind: .letter, rank: 4, group: "CJK Compatibility Ideographs"),
            character(eAcute, "latin small letter e with acute", kind: .letter, rank: 3, group: "Latin-1 Supplement"),
            character(plus, "plus sign", rank: 1, group: "Basic Latin", keywords: ["+", "add"]),
            character(numberSign, "number sign", kind: .punctuation, rank: 2, group: "Basic Latin", keywords: ["hash", "pound"]),
            character(noBreakSpace, "no-break space", kind: .space, rank: 2, group: "Latin-1 Supplement", keywords: ["nbsp"], aliases: [alias("nbsp")]),
            character(ohm, "ohm sign", rank: 2, group: "Letterlike Symbols", aliases: [alias("ohm")]),
            character(omega, "greek capital letter omega", kind: .letter, rank: 3, group: "Greek and Coptic", aliases: [alias("omega")])
        ]
        let ranges = [
            CodePointRange(first: 0x4E00, last: 0x9FFF, rule: .hexSuffix(prefix: "CJK UNIFIED IDEOGRAPH-"), group: "CJK Unified Ideographs", age: age("1.1")),
            CodePointRange(first: 0xAC00, last: 0xD7A3, rule: .hangulSyllable, group: "Hangul Syllables", age: age("2.0"))
        ]
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        return SearchIndex(catalog: Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: ranges)))
    }()

    private func strings(_ query: String, options: SearchOptions = SearchOptions()) -> [String] {
        Self.index.search(query, options: options).map(\.entry.string)
    }

    private func assertResults(_ query: String, _ expected: [String], options: SearchOptions = SearchOptions(), file: StaticString = #filePath, line: UInt = #line) {
        let actual = strings(query, options: options)
        XCTAssertEqual(actual.count, expected.count, "\(query): got \(actual.map(\.codePointDescription))", file: file, line: line)
        for (got, want) in zip(actual, expected) {
            XCTAssertTrue(got.isExactly(want), "\(query): got \(actual.map(\.codePointDescription)), want \(expected.map(\.codePointDescription))", file: file, line: line)
        }
    }

    // MARK: - Aliases and exact matches

    func testCuratedAliasOrderLeadsThenKeywordMatchesThenNameWords() {
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.bow, Self.rightArrowEmoji, Self.upRightArrow, Self.strokeArrow])
    }

    func testPunctuationAliases() {
        assertResults("->", [Self.rightArrow])
        assertResults("<-", [Self.leftArrow])
        assertResults("!=", [Self.notEqual])
    }

    func testSingleLetterPrefersTheCuratedAliasOverTheLetter() {
        assertResults("x", [Self.times, Self.letterX])
    }

    func testAliasIsCaseInsensitive() {
        assertResults("CMD", [Self.command])
        assertResults("Tick", [Self.check])
    }

    func testAliasPrefixAlreadyFindsTheEntry() {
        assertResults("cm", [Self.command])
    }

    func testExactNameOutranksExactKeyword() {
        assertResults("fire", [Self.fire, Self.fireEngine])
    }

    func testKeywordOnlyMatch() {
        assertResults("happy", [Self.grin])
    }

    func testOfficialNameKeyword() {
        assertResults("rightwards arrow", [Self.rightArrow, Self.strokeArrow])
    }

    func testHyphenatedNameMatchesSpacedQuery() {
        assertResults("up right", [Self.upRightArrow])
        XCTAssertEqual(Self.index.search("up-right arrow").first?.tier, .exact)
        XCTAssertEqual(Self.index.search("up right arrow").first?.tier, .exact)
    }

    func testAliasThenWholeWordInName() {
        assertResults("heart", [Self.redHeart, Self.textHeart])
    }

    func testSkinToneVariantsStayOutOfWordResults() {
        assertResults("thumbs up", [Self.thumbsUp])
        assertResults("medium skin tone", [])
    }

    func testCanonicallyEquivalentEntriesAreSeparate() {
        assertResults("ohm", [Self.ohm])
        assertResults("omega", [Self.omega])
        XCTAssertEqual(Self.index.search("\u{2126}").first?.entry.name, "ohm sign")
        XCTAssertEqual(Self.index.search("\u{3A9}").first?.entry.name, "greek capital letter omega")
    }

    func testBlockNameFindsItsCharactersThenNearMisses() {
        // The four characters of the Arrows block match the block name as a
        // whole word. With fewer than eight hits the near-miss pass adds the
        // entries whose word `arrow` is one edit away. Both have it in their
        // name and share a rank, so catalogue order decides.
        assertResults("arrows", [Self.leftArrow, Self.rightArrow, Self.upRightArrow, Self.strokeArrow, Self.bow, Self.rightArrowEmoji])
        XCTAssertEqual(Self.index.search("arrows").map(\.tier), [.prefix, .prefix, .prefix, .prefix, .fuzzy, .fuzzy])
    }

    func testBlockNameFragmentsAreNotSearchWords() {
        // "Latin-1 Supplement" must not attach its characters to the query 1.
        XCTAssertFalse(strings("1").contains { $0.isExactly(Self.noBreakSpace) || $0.isExactly(Self.eAcute) })
    }

    // MARK: - Code points

    func testExplicitCodePointFindsExactlyThatCharacter() {
        assertResults("U+0078", [Self.letterX])
        assertResults("u+2192", [Self.rightArrow])
        XCTAssertEqual(Self.index.search("U+2192").first?.tier, .codePoint)
    }

    func testExplicitSequenceIsParsedAsAWhole() {
        assertResults("U+1F44D U+1F3FD", [Self.thumbsUpMedium])
        assertResults("U+2764, U+FE0F", [Self.redHeart])
    }

    func testBareHexIsASecondaryReading() {
        assertResults("2192", [Self.rightArrow])
        XCTAssertEqual(Self.index.search("2192").first?.tier, .bareCodePoint)
        // `face` is a keyword first and U+FACE second.
        assertResults("face", [Self.grin, Self.ideographFace])
        // `100` is the hundred-points keyword first and U+0100 second.
        assertResults("100", [Self.hundred, Self.aMacron])
    }

    func testBareHexInAnAlgorithmicRangeIsSynthesised() {
        let hits = Self.index.search("cafe")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.entry.string, "\u{CAFE}")
        XCTAssertNil(hits.first?.index)
        XCTAssertTrue(hits.first?.entry.name.hasPrefix("hangul syllable") ?? false)
    }

    func testInvalidCodePointsAreRejectedGracefully() {
        assertResults("U+D800", [])
        assertResults("U+110000", [])
        assertResults("U+ZZZZ", [])
        assertResults("U+0007", [])
    }

    // MARK: - Literals

    func testPastedCharacterFindsItself() {
        assertResults(Self.rightArrow, [Self.rightArrow])
        XCTAssertEqual(Self.index.search(Self.rightArrow).first?.tier, .literal)
        assertResults(Self.eAcute, [Self.eAcute])
    }

    func testPastedVariantAndSequenceAreFoundExactly() {
        // A pasted sequence that is itself an entry is not taken apart.
        assertResults(Self.thumbsUpMedium, [Self.thumbsUpMedium])
        assertResults(Self.redHeart, [Self.redHeart])
        assertResults(Self.textHeart, [Self.textHeart])
    }

    func testPastedUnknownSequenceFallsBackToItsScalars() {
        // x followed by a combining acute is not an entry; its base letter is.
        assertResults("\u{2192}\u{301}", [Self.rightArrow])
    }

    func testSeveralPastedCharactersKeepTheirOrder() {
        assertResults(Self.leftArrow + Self.rightArrow, [Self.leftArrow, Self.rightArrow])
    }

    func testPastedIdeographResolvesThroughItsRange() {
        let hits = Self.index.search("\u{4E2D}")
        XCTAssertEqual(hits.map(\.entry.name), ["cjk unified ideograph-4e2d"])
    }

    func testAsciiPunctuationFallsBackToTheCharacterItself() {
        assertResults("#", [Self.numberSign])
        assertResults("+", [Self.plus])
    }

    func testSymbolicKeywordWithDigits() {
        // `+1` is a keyword of thumbs up; `1` also starts the `100` keyword.
        assertResults("+1", [Self.thumbsUp, Self.hundred])
    }

    // MARK: - Substring and fuzzy

    func testSubstringTier() {
        let hits = Self.index.search("finit")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
        XCTAssertEqual(hits.first?.tier, .substring)
    }

    func testFuzzyOnlyForGenuineNearMisses() {
        let hits = Self.index.search("infinty")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
        XCTAssertEqual(hits.first?.tier, .fuzzy)
        // Three letters are too few to correct.
        assertResults("arw", [])
    }

    func testAccentsInTheQueryAreFolded() {
        let hits = Self.index.search("Infinit\u{E9}")
        XCTAssertEqual(hits.map(\.entry.string), [Self.infinity])
    }

    // MARK: - Ordering rules

    func testFavouriteBreaksTiesInsideATierOnly() {
        var options = SearchOptions()
        options.favourites = [Self.upRightArrow.exact, Self.strokeArrow.exact]
        // The favourite leads the keyword matches but stays behind the alias
        // matches, and the name-word match stays in its later tier.
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.upRightArrow, Self.bow, Self.rightArrowEmoji, Self.strokeArrow], options: options)
    }

    func testRecentRanksBelowFavouriteInATie() {
        var options = SearchOptions()
        options.recents = [Self.rightArrowEmoji.exact]
        options.favourites = [Self.upRightArrow.exact]
        assertResults("arrow", [Self.rightArrow, Self.leftArrow, Self.upRightArrow, Self.rightArrowEmoji, Self.bow, Self.strokeArrow], options: options)
    }

    func testLimitAndEmptyQueries() {
        var options = SearchOptions()
        options.limit = 2
        assertResults("arrow", [Self.rightArrow, Self.leftArrow], options: options)
        assertResults("", [])
        assertResults("   ", [])
    }

    func testCancellationReturnsNothing() {
        let options = SearchOptions(isCancelled: { true })
        assertResults("arrow", [], options: options)
    }

    func testResultsAreDeterministic() {
        for query in ["arrow", "a", "e", "fire", "x", "latin"] {
            XCTAssertEqual(strings(query), strings(query), query)
        }
    }

    func testNoResult() {
        assertResults("zzzzqqq", [])
    }
}

final class SearchTextTests: XCTestCase {
    func testFoldLowercasesAndStripsDiacritics() {
        XCTAssertEqual(SearchText.fold("RIGHT Arrow"), "right arrow")
        XCTAssertEqual(SearchText.fold("Caf\u{E9}"), "cafe")
        XCTAssertEqual(SearchText.fold("\u{FF21}"), "a")
    }

    func testTokensSplitOnAnythingButLettersAndDigits() {
        func words(_ text: String) -> [String] { SearchText.tokens(text).map { String(decoding: $0, as: UTF8.self) } }
        XCTAssertEqual(words("up-right arrow"), ["up", "right", "arrow"])
        XCTAssertEqual(words("people & body/hand-fingers"), ["people", "body", "hand", "fingers"])
        XCTAssertEqual(words("+1"), ["1"])
        XCTAssertEqual(words("->"), [])
        XCTAssertEqual(words("\u{3B1}\u{3B2} \u{3B3}"), ["\u{3B1}\u{3B2}", "\u{3B3}"])
    }

    func testEditDistanceCountsTranspositionAsOne() {
        func distance(_ a: String, _ b: String, limit: Int = 3) -> Int {
            Array(b.utf8).withUnsafeBufferPointer { SearchText.editDistance(Array(a.utf8), $0, limit: limit) }
        }
        XCTAssertEqual(distance("arrow", "arrow"), 0)
        XCTAssertEqual(distance("arorw", "arrow"), 1)
        XCTAssertEqual(distance("arow", "arrow"), 1)
        XCTAssertEqual(distance("infinty", "infinity"), 1)
        XCTAssertEqual(distance("kitten", "sitting"), 3)
        XCTAssertGreaterThan(distance("abcdef", "uvwxyz", limit: 2), 2)
    }

    func testCodePointQueryParsing() {
        XCTAssertEqual(CodePointQuery.parse("U+2192"), CodePointQuery(string: "\u{2192}", isExplicit: true))
        XCTAssertEqual(CodePointQuery.parse("u+1f469 u+200d u+1f4bb"), CodePointQuery(string: "\u{1F469}\u{200D}\u{1F4BB}", isExplicit: true))
        XCTAssertEqual(CodePointQuery.parse("1F44D"), CodePointQuery(string: "\u{1F44D}", isExplicit: false))
        XCTAssertEqual(CodePointQuery.parse("U+2764,U+FE0F")?.string.unicodeScalars.count, 2)
        XCTAssertNil(CodePointQuery.parse("arrow"))
        XCTAssertNil(CodePointQuery.parse("U+D800"))
        XCTAssertNil(CodePointQuery.parse("U+110000"))
        XCTAssertNil(CodePointQuery.parse("U+2192 zz"))
        XCTAssertNil(CodePointQuery.parse("f"))
        XCTAssertNil(CodePointQuery.parse("1234567"))
    }
}
