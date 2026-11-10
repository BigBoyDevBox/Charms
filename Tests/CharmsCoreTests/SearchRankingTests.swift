import XCTest
@testable import CharmsCore

/// Ordering rules that only show with several competing entries. Each
/// fixture reproduces a wrong order that the full catalogue once produced.
final class SearchRankingTests: XCTestCase {
    private static let hyphen = "-"
    private static let greater = ">"
    private static let rightArrow = "\u{2192}"
    private static let doubleArrow = "\u{21D2}"
    private static let palette = "\u{1F3A8}"
    private static let alef = "\u{627}"
    private static let ginger = "\u{1FADA}"
    private static let beer = "\u{1F37A}"
    private static let monkey = "\u{1F648}"
    private static let gesturingNo = "\u{1F645}"

    private static func entry(_ string: String, _ name: String, _ kind: CatalogEntry.Kind, rank: UInt8, keywords: [String] = [], aliases: [CatalogAlias] = []) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: aliases.isEmpty ? rank : 0, age: UnicodeAge(major: 1, minor: 1), group: "Test", name: name, keywords: keywords, aliases: aliases)
    }

    private static let index: SearchIndex = {
        // Index order is deliberately the opposite of the wanted result
        // order wherever a rule has to decide.
        let entries = [
            entry(ginger, "ginger root", .emoji, rank: 1, keywords: ["beer", "root", "spice"]),
            entry(beer, "beer mug", .emoji, rank: 1, keywords: ["bar", "beer", "drink"]),
            entry(monkey, "see-no-evil monkey", .emoji, rank: 1, keywords: ["evil", "no", "see"]),
            entry(gesturingNo, "person gesturing NO", .emoji, rank: 1, keywords: ["forbidden", "no"]),
            entry(palette, "artist palette", .emoji, rank: 1, keywords: ["art", "museum"]),
            entry(hyphen, "hyphen-minus", .punctuation, rank: 2),
            entry(greater, "greater-than sign", .symbol, rank: 2),
            entry(alef, "arabic letter alef", .letter, rank: 4),
            entry(doubleArrow, "rightwards double arrow", .symbol, rank: 2, aliases: [CatalogAlias(text: "arrow", rank: 1), CatalogAlias(text: "->", rank: 1)]),
            entry(rightArrow, "rightwards arrow", .symbol, rank: 2, aliases: [CatalogAlias(text: "arrow", rank: 0), CatalogAlias(text: "->", rank: 0)])
        ]
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        return SearchIndex(catalog: Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: [])))
    }()

    private func strings(_ query: String) -> [String] {
        Self.index.search(query).map(\.entry.string)
    }

    func testPunctuationAliasComesBeforeTheCharactersItIsTypedWith() {
        // `->` is a name for the arrow. The hyphen and the greater-than
        // sign stay reachable, after it.
        XCTAssertEqual(strings("->"), [Self.rightArrow, Self.doubleArrow, Self.hyphen, Self.greater])
    }

    func testPunctuationWithoutAnAliasFindsTheCharacterItself() {
        XCTAssertEqual(strings("-"), [Self.hyphen])
        XCTAssertEqual(strings(">"), [Self.greater])
    }

    func testAliasBeingTypedLeadsOtherPrefixMatches() {
        // On the way to "arrow", the arrows are already first and in their
        // curated order; other prefix matches follow by rank.
        XCTAssertEqual(strings("ar"), [Self.rightArrow, Self.doubleArrow, Self.palette, Self.alef])
        XCTAssertEqual(strings("arr"), [Self.rightArrow, Self.doubleArrow])
    }

    func testCompletedAliasKeepsTheSameOrder() {
        XCTAssertEqual(strings("arrow"), [Self.rightArrow, Self.doubleArrow])
    }

    func testKeywordThatIsAWordOfTheNameComesFirst() {
        // Both carry the keyword "beer"; only one is called a beer.
        XCTAssertEqual(strings("beer"), [Self.beer, Self.ginger])
    }

    func testPartOfAHyphenatedNameIsNotAStandaloneWord() {
        // "no" inside "see-no-evil" does not make the monkey the answer to
        // "no".
        XCTAssertEqual(strings("no"), [Self.gesturingNo, Self.monkey])
    }
}
