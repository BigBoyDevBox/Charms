import XCTest
@testable import CharmsCore

final class PickerContentTests: XCTestCase {
    private static let thumbsUp = "\u{1F44D}"
    private static let thumbsUpLight = "\u{1F44D}\u{1F3FB}"
    private static let thumbsUpMedium = "\u{1F44D}\u{1F3FD}"
    private static let grin = "\u{1F600}"
    private static let newEmoji = "\u{1FAEB}"
    private static let rightArrow = "\u{2192}"
    private static let leftArrow = "\u{2190}"
    private static let acute = "\u{301}"
    private static let noBreakSpace = "\u{A0}"
    private static let angstrom = "\u{212B}"
    private static let aRing = "\u{C5}"

    private static func entry(_ string: String, _ name: String, _ kind: CatalogEntry.Kind, keywords: [String] = [], aliases: [CatalogAlias] = []) -> CatalogEntry {
        CatalogEntry(string: string, kind: kind, rank: aliases.isEmpty ? 2 : 0, age: UnicodeAge(major: 1, minor: 1), group: "Test", name: name, keywords: keywords, aliases: aliases)
    }

    private static let content: PickerContent = {
        let entries = [
            entry(thumbsUp, "thumbs up", .emoji, keywords: ["hand", "thumb"]),
            entry(thumbsUpLight, "thumbs up: light skin tone", .variant),
            entry(thumbsUpMedium, "thumbs up: medium skin tone", .variant),
            entry(grin, "grinning face", .emoji, keywords: ["happy"]),
            entry(newEmoji, "newly added face", .emoji, keywords: ["happy"]),
            entry(noBreakSpace, "no-break space", .space, aliases: [CatalogAlias(text: "nbsp", rank: 0)]),
            entry(aRing, "latin capital letter a with ring above", .letter),
            entry(acute, "combining acute accent", .mark),
            entry(leftArrow, "leftwards arrow", .symbol, aliases: [CatalogAlias(text: "arrow", rank: 1)]),
            entry(rightArrow, "rightwards arrow", .symbol, aliases: [CatalogAlias(text: "arrow", rank: 0)]),
            entry(angstrom, "angstrom sign", .symbol)
        ]
        let header = CatalogFormat.Header(unicodeVersion: "18.0.0", emojiVersion: "18.0", cldrVersion: "49")
        let catalog = Catalog(contents: CatalogFormat.Contents(header: header, entries: entries, ranges: []))
        return PickerContent(catalog: catalog, index: SearchIndex(catalog: catalog))
    }()

    private func sections(_ query: String, library: UserLibrary = UserLibrary(), tone: SkinTone = .none, columns: Int = 8, unsupported: Set<String> = []) -> [PickerSection] {
        Self.content.sections(query: query, library: library, skinTone: tone, columns: columns, isSupported: { !unsupported.contains($0.string) })
    }

    private func results(_ query: String, library: UserLibrary = UserLibrary(), tone: SkinTone = .none, unsupported: Set<String> = []) -> [String] {
        sections(query, library: library, tone: tone, unsupported: unsupported).first?.items.map(\.string) ?? []
    }

    private func library(favourites: [String] = [], recents: [String] = []) -> UserLibrary {
        var library = UserLibrary()
        library.seedIfNeeded(favourites.map { LibraryItem(string: $0, name: "saved \($0)") })
        for string in recents.reversed() {
            library.recordUse(LibraryItem(string: string, name: "saved \(string)"))
        }
        return library
    }

    // MARK: Empty query

    func testEmptyQueryShowsFavouritesThenRecents() {
        let shown = sections("", library: library(favourites: [Self.rightArrow, Self.grin], recents: [Self.leftArrow]))
        XCTAssertEqual(shown.map(\.kind), [.favourites, .recents])
        XCTAssertEqual(shown[0].items.map(\.string), [Self.rightArrow, Self.grin])
        XCTAssertEqual(shown[1].items.map(\.string), [Self.leftArrow])
        XCTAssertTrue(shown[0].items.allSatisfy(\.isFavourite))
        XCTAssertFalse(shown[1].items[0].isFavourite)
    }

    func testWhitespaceOnlyQueryCountsAsEmpty() {
        XCTAssertEqual(sections("   ").map(\.kind), [.favourites, .recents])
    }

    func testRecentAlreadyShownAsFavouriteIsNotRepeated() {
        let shown = sections("", library: library(favourites: [Self.rightArrow], recents: [Self.rightArrow, Self.grin]))
        XCTAssertEqual(shown[1].items.map(\.string), [Self.grin])
    }

    func testSectionsAreLimitedToTwoRowsEach() {
        let many = (0..<30).map { String(UnicodeScalar(UInt32(0x2460 + $0))!) }
        let shown = sections("", library: library(favourites: many, recents: many.reversed()), columns: 4)
        XCTAssertEqual(shown[0].items.count, 8)
        XCTAssertLessThanOrEqual(shown[1].items.count, 8)
    }

    func testSavedItemTakesItsNameFromTheCatalogue() {
        let shown = sections("", library: library(favourites: [Self.rightArrow]))
        XCTAssertEqual(shown[0].items[0].name, "Rightwards arrow", "names are shown with a capital first letter")
    }

    func testSavedItemMissingFromTheCatalogueKeepsItsStoredName() {
        let shown = sections("", library: library(favourites: ["\u{2460}"]))
        XCTAssertEqual(shown[0].items[0].name, "saved \u{2460}")
        XCTAssertEqual(shown[0].items[0].string, "\u{2460}")
    }

    func testFavouriteKeepsItsExactVariantWhateverTheSkinTonePreference() {
        let shown = sections("", library: library(favourites: [Self.thumbsUpLight]), tone: .medium)
        XCTAssertEqual(shown[0].items.map(\.string), [Self.thumbsUpLight])
    }

    // MARK: Results

    func testQueryShowsOneResultSection() {
        let shown = sections("arrow")
        XCTAssertEqual(shown.map(\.kind), [.results])
        XCTAssertEqual(shown[0].items.map(\.string), [Self.rightArrow, Self.leftArrow])
    }

    func testResultsMarkFavourites() {
        let shown = sections("arrow", library: library(favourites: [Self.leftArrow]))
        let flags = Dictionary(uniqueKeysWithValues: shown[0].items.map { ($0.string, $0.isFavourite) })
        XCTAssertEqual(flags[Self.leftArrow], true)
        XCTAssertEqual(flags[Self.rightArrow], false)
    }

    func testPreferredSkinToneReplacesTheBaseEmoji() {
        XCTAssertEqual(results("thumbs", tone: .medium), [Self.thumbsUpMedium])
        XCTAssertEqual(results("thumbs", tone: .none), [Self.thumbsUp])
    }

    func testPreferredSkinToneFallsBackToTheBaseWhenThatVariantIsMissing() {
        // The fixture defines light and medium only.
        XCTAssertEqual(results("thumbs", tone: .dark), [Self.thumbsUp])
    }

    func testPreferredSkinToneFallsBackWhenTheVariantCannotBeDrawn() {
        XCTAssertEqual(results("thumbs", tone: .medium, unsupported: [Self.thumbsUpMedium]), [Self.thumbsUp])
    }

    func testEmojiWithoutVariantsIgnoresTheSkinTone() {
        XCTAssertEqual(results("grinning", tone: .medium), [Self.grin])
    }

    func testUnsupportedEntriesAreLeftOutOfWordSearch() {
        XCTAssertEqual(results("happy", unsupported: [Self.newEmoji]), [Self.grin])
        XCTAssertEqual(Set(results("happy")), [Self.grin, Self.newEmoji])
    }

    func testExplicitRequestsShowEvenWhatCannotBeDrawn() {
        XCTAssertEqual(results("U+1FAEB", unsupported: [Self.newEmoji]), [Self.newEmoji])
        XCTAssertEqual(results(Self.newEmoji, unsupported: [Self.newEmoji]), [Self.newEmoji])
    }

    func testLiteralVariantIsShownAsTyped() {
        XCTAssertEqual(results(Self.thumbsUpLight, tone: .medium), [Self.thumbsUpLight])
    }

    func testCanonicallyEquivalentCharactersStayDistinct() {
        // U+212B and U+00C5 are equal to Swift's String ==, but they are
        // different characters to insert.
        XCTAssertEqual(results("U+212B").map(\.codePointDescription), ["U+212B"])
        XCTAssertEqual(results("U+00C5").map(\.codePointDescription), ["U+00C5"])
    }

    // MARK: Items

    func testVariantBaseIsOfferedForBaseAndVariant() {
        let base = sections("thumbs")[0].items[0]
        XCTAssertEqual(base.variantBaseIndex, 0)
        let variant = sections(Self.thumbsUpMedium)[0].items[0]
        XCTAssertEqual(variant.variantBaseIndex, 0)
        XCTAssertNil(sections("grinning")[0].items[0].variantBaseIndex)
        XCTAssertNil(sections("arrow")[0].items[0].variantBaseIndex)
    }

    func testVariantsListTheBaseFirstThenSupportedVariants() {
        let all = Self.content.variants(ofBaseAt: 0, library: UserLibrary(), isSupported: { _ in true })
        XCTAssertEqual(all.map(\.string), [Self.thumbsUp, Self.thumbsUpLight, Self.thumbsUpMedium])
        let limited = Self.content.variants(ofBaseAt: 0, library: UserLibrary(), isSupported: { $0.string != Self.thumbsUpLight })
        XCTAssertEqual(limited.map(\.string), [Self.thumbsUp, Self.thumbsUpMedium])
        XCTAssertTrue(Self.content.variants(ofBaseAt: 3, library: UserLibrary(), isSupported: { _ in true }).isEmpty)
        XCTAssertTrue(Self.content.variants(ofBaseAt: 99, library: UserLibrary(), isSupported: { _ in true }).isEmpty)
    }

    func testInvisibleCharactersGetAVisiblePreviewButKeepTheirString() {
        let space = sections("nbsp")[0].items[0]
        XCTAssertEqual(space.string, Self.noBreakSpace)
        XCTAssertEqual(space.preview, "\u{2423}")
        let mark = sections("combining acute")[0].items[0]
        XCTAssertEqual(mark.string, Self.acute)
        XCTAssertEqual(mark.preview, "\u{25CC}\u{301}")
        let arrow = sections("arrow")[0].items[0]
        XCTAssertEqual(arrow.preview, arrow.string)
    }

    func testItemsCarryNameAndCodePoints() {
        let item = sections(Self.thumbsUpMedium)[0].items[0]
        XCTAssertEqual(item.name, "Thumbs up: medium skin tone")
        XCTAssertEqual(item.codePoints, "U+1F44D U+1F3FD")
        XCTAssertTrue(item.isEmoji)
    }

    func testSeedFavouritesKeepOnlyStringsTheCatalogueLists() {
        let seed = SeedFavourites.items(in: Self.content.catalog)
        XCTAssertEqual(seed.map(\.string), [Self.rightArrow, Self.thumbsUp])
        XCTAssertEqual(seed.first?.name, "Rightwards arrow")
    }
}
