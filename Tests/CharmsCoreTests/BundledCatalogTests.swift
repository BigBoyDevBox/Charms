import XCTest
@testable import CharmsCore

/// Checks on the generated catalogue that ships in the app: that it loads,
/// that it keeps the invariants the app relies on, and that the searches a
/// person is most likely to type find what they mean.
final class BundledCatalogTests: XCTestCase {
    private static let loaded: (catalog: Catalog, index: SearchIndex) = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/catalog.txt")
        do {
            let catalog = try Catalog(data: Data(contentsOf: url))
            return (catalog, SearchIndex(catalog: catalog))
        } catch {
            fatalError("Resources/catalog.txt could not be loaded: \(error)")
        }
    }()

    private var catalog: Catalog { Self.loaded.catalog }
    private var index: SearchIndex { Self.loaded.index }

    // MARK: Invariants

    func testEntriesAreUniqueByScalarSequence() {
        var seen = Set<ExactString>()
        for entry in catalog.entries {
            XCTAssertTrue(seen.insert(entry.string.exact).inserted, "duplicate \(entry.string.codePointDescription)")
        }
        XCTAssertGreaterThan(catalog.entries.count, 40_000)
    }

    func testEveryEntryFitsOneKeyboardEvent() {
        // Insertion sends an entry in one event, which carries at most
        // `InsertionPolicy.maximumUnitsPerEvent` UTF-16 units.
        for entry in catalog.entries {
            XCTAssertEqual(InsertionPolicy.eventPayloads(for: entry.string).count, 1, entry.string.codePointDescription)
        }
    }

    func testEveryVariantFollowsABase() {
        for (position, entry) in catalog.entries.enumerated() where entry.kind == .variant {
            XCTAssertNotNil(catalog.base(ofVariantAt: position), entry.string.codePointDescription)
        }
    }

    func testSeedFavouritesAreAllInTheCatalogue() {
        XCTAssertEqual(SeedFavourites.items(in: catalog).map(\.string), SeedFavourites.strings)
    }

    // MARK: Searches

    /// Query, then the scalar sequence expected first.
    private static let firstResults: [(String, String)] = [
        ("arrow", "\u{2192}"), ("ar", "\u{2192}"), ("arr", "\u{2192}"), ("->", "\u{2192}"),
        ("rightwards arrow", "\u{2192}"), ("U+2192", "\u{2192}"), ("2192", "\u{2192}"),
        ("up right", "\u{2197}"), ("<=", "\u{2264}"), ("=>", "\u{21D2}"), ("!=", "\u{2260}"),
        ("check", "\u{2713}"), ("tick", "\u{2713}"), ("x", "\u{D7}"), ("times", "\u{D7}"),
        ("infinity", "\u{221E}"), ("deg", "\u{B0}"), ("tm", "\u{2122}"), ("euro", "\u{20AC}"),
        ("copyright", "\u{A9}"), ("pi", "\u{3C0}"), ("lambda", "\u{3BB}"), ("omega", "\u{3C9}"),
        ("sum", "\u{2211}"), ("sqrt", "\u{221A}"), ("approx", "\u{2248}"), ("half", "\u{BD}"),
        ("1/2", "\u{BD}"), ("plus minus", "\u{B1}"), ("divide", "\u{F7}"), ("dagger", "\u{2020}"),
        ("pilcrow", "\u{B6}"), ("section", "\u{A7}"), ("bullet", "\u{2022}"), ("ellipsis", "\u{2026}"),
        ("em dash", "\u{2014}"), ("dash", "\u{2014}"), ("quote", "\u{201C}"), ("guillemet", "\u{AB}"),
        ("nbsp", "\u{A0}"), ("zero width", "\u{200B}"),
        ("cmd", "\u{2318}"), ("command", "\u{2318}"), ("option", "\u{2325}"), ("shift", "\u{21E7}"),
        ("return", "\u{21B5}"), ("enter", "\u{21B5}"), ("tab", "\u{21E5}"), ("esc", "\u{238B}"),
        ("delete", "\u{232B}"), ("apple", "\u{F8FF}"),
        ("heart", "\u{2764}\u{FE0F}"), ("thumbs up", "\u{1F44D}"), ("100", "\u{1F4AF}"),
        ("technologist", "\u{1F9D1}\u{200D}\u{1F4BB}"), ("switzerland", "\u{1F1E8}\u{1F1ED}"),
        ("shrug", "\u{1F937}"), ("fire", "\u{1F525}"), ("party", "\u{1F389}"), ("rocket", "\u{1F680}"),
        ("coffee", "\u{2615}"), ("cafe", "\u{2615}"), ("beer", "\u{1F37A}"), ("pizza", "\u{1F355}"),
        ("thinking", "\u{1F914}"), ("sob", "\u{1F62D}"), ("joy", "\u{1F602}"), ("no", "\u{1F645}"),
        // Near misses.
        ("infinty", "\u{221E}"), ("grinnig", "\u{1F600}")
    ]

    func testCommonSearchesFindWhatTheyName() {
        for (query, expected) in Self.firstResults {
            let first = index.search(query).first?.entry.string
            XCTAssertTrue(first?.isExactly(expected) ?? false, "\(query): got \(first?.codePointDescription ?? "nothing"), want \(expected.codePointDescription)")
        }
    }

    func testExplicitCodePointGivesExactlyThatCharacter() {
        XCTAssertEqual(index.search("U+2192").map(\.entry.string), ["\u{2192}"])
        XCTAssertEqual(index.search("U+00C5").map(\.entry.string.codePointDescription), ["U+00C5"])
        XCTAssertEqual(index.search("U+212B").map(\.entry.string.codePointDescription), ["U+212B"])
    }

    func testPunctuationAliasKeepsItsCharactersReachable() {
        let found = index.search("->").map(\.entry.string)
        XCTAssertEqual(found.first, "\u{2192}")
        XCTAssertTrue(found.contains("-"))
        XCTAssertTrue(found.contains(">"))
    }

    func testEmojiSearchesLeadWithEmoji() {
        for query in ["happy", "smile", "face", "cat", "dog", "tree", "laugh", "cry"] {
            let kinds = index.search(query).prefix(3).map(\.entry.kind)
            XCTAssertEqual(kinds.first, .emoji, query)
        }
    }

    func testSkinToneVariantsDoNotCrowdWordResults() {
        XCTAssertFalse(index.search("thumbs up").contains { $0.entry.kind == .variant })
        XCTAssertFalse(index.search("wave").contains { $0.entry.kind == .variant })
    }

    // MARK: Speed

    func testSearchStaysInteractive() {
        // The picker searches on the main thread at every keystroke. An
        // optimised build answers the worst of these in under 30 ms
        // (measured, Apple silicon); the bound here is loose enough for an
        // unoptimised test build on a slow runner and still catches a
        // search that has become quadratic.
        let queries = Self.firstResults.map(\.0) + ["a", "e", "s", "la", "co", "small", "letter a", "latin small letter"]
        let start = Date()
        for query in queries {
            _ = index.search(query)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 20)
    }
}
