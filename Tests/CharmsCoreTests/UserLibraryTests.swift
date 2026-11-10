import XCTest
@testable import CharmsCore

final class UserLibraryTests: XCTestCase {
    private let seed = [
        LibraryItem(string: "\u{2192}", name: "right arrow"),
        LibraryItem(string: "\u{1F44D}", name: "thumbs up"),
        LibraryItem(string: "\u{2764}", name: "heart")
    ]

    // MARK: - Seeding

    func testFirstRunSeedsFavouritesAtCurrentSchema() {
        var library = UserLibrary()
        XCTAssertFalse(library.isSeeded)
        XCTAssertTrue(library.favourites.isEmpty)
        XCTAssertTrue(library.recents.isEmpty)
        XCTAssertEqual(library.schemaVersion, 1)

        library.seedIfNeeded(seed)

        XCTAssertTrue(library.isSeeded)
        XCTAssertEqual(library.favourites, seed)
        XCTAssertEqual(library.schemaVersion, UserLibrary.currentSchemaVersion)
    }

    func testSeedingHappensOnlyOnce() {
        var library = UserLibrary()
        library.seedIfNeeded(seed)
        library.toggleFavourite(LibraryItem(string: "\u{1F600}", name: "grinning face"))
        library.seedIfNeeded([
            LibraryItem(string: "\u{1F44F}", name: "clapping hands")
        ])
        XCTAssertEqual(library.favourites.map(\.string), ["\u{2192}", "\u{1F44D}", "\u{2764}", "\u{1F600}"])
    }

    func testRemovingLastFavouriteStaysEmptyAfterReseed() {
        var library = UserLibrary()
        library.seedIfNeeded(seed)
        for item in seed {
            library.removeFavourite(item.string)
        }
        XCTAssertTrue(library.favourites.isEmpty)

        library.seedIfNeeded(seed)

        XCTAssertTrue(library.favourites.isEmpty)
        XCTAssertTrue(library.isSeeded)
    }

    func testSeedDeduplicatesByExactStringFirstWins() {
        var library = UserLibrary()
        library.seedIfNeeded([
            LibraryItem(string: "x", name: "first"),
            LibraryItem(string: "x", name: "second"),
            LibraryItem(string: "\u{C5}", name: "a with ring"),
            LibraryItem(string: "\u{212B}", name: "angstrom sign")
        ])
        XCTAssertEqual(library.favourites, [
            LibraryItem(string: "x", name: "first"),
            LibraryItem(string: "\u{C5}", name: "a with ring"),
            LibraryItem(string: "\u{212B}", name: "angstrom sign")
        ])
    }

    // MARK: - Favourites

    func testToggleAddsAtEndAndRemoves() {
        var library = UserLibrary()
        XCTAssertTrue(library.toggleFavourite(LibraryItem(string: "m", name: "em")))
        XCTAssertTrue(library.toggleFavourite(LibraryItem(string: "n", name: "en")))
        XCTAssertEqual(library.favourites.map(\.string), ["m", "n"])

        XCTAssertFalse(library.toggleFavourite(LibraryItem(string: "m", name: "different name")))

        XCTAssertEqual(library.favourites.map(\.string), ["n"])
    }

    func testMoveFavouriteLeftRightClampedAndAbsent() {
        var library = UserLibrary()
        library.seedIfNeeded([
            LibraryItem(string: "a", name: "A"),
            LibraryItem(string: "b", name: "B"),
            LibraryItem(string: "c", name: "C"),
            LibraryItem(string: "d", name: "D")
        ])

        XCTAssertTrue(library.moveFavourite("c", by: -2))
        XCTAssertEqual(library.favourites.map(\.string), ["c", "a", "b", "d"])

        XCTAssertTrue(library.moveFavourite("c", by: 3))
        XCTAssertEqual(library.favourites.map(\.string), ["a", "b", "d", "c"])

        XCTAssertFalse(library.moveFavourite("c", by: 5))
        XCTAssertFalse(library.moveFavourite("a", by: -5))
        XCTAssertFalse(library.moveFavourite("a", by: 0))
        XCTAssertFalse(library.moveFavourite("z", by: 1))
        XCTAssertEqual(library.favourites.map(\.string), ["a", "b", "d", "c"])
    }

    func testResetFavouritesRestoresSeedAndKeepsRecents() {
        var library = UserLibrary()
        library.seedIfNeeded(seed)
        library.recordUse(LibraryItem(string: "\u{1F600}", name: "grinning face"))
        library.removeFavourite("\u{2192}")

        library.resetFavourites(to: seed)

        XCTAssertEqual(library.favourites, seed)
        XCTAssertEqual(library.recents.map(\.string), ["\u{1F600}"])
    }

    // MARK: - Recents

    func testRecordUseDedupesByExactScalarsAndMovesToFront() {
        var library = UserLibrary()
        library.recordUse(LibraryItem(string: "p", name: "first name"))
        library.recordUse(LibraryItem(string: "q", name: "Q"))
        library.recordUse(LibraryItem(string: "p", name: "updated name"))
        XCTAssertEqual(library.recents.map(\.string), ["p", "q"])
        XCTAssertEqual(library.recents.first?.name, "updated name")
    }

    func testRecentsAreCappedAtFiftyWithOldestDropped() {
        var library = UserLibrary()
        for index in 0..<60 {
            library.recordUse(LibraryItem(string: "char-\(index)", name: "char \(index)"))
        }
        XCTAssertEqual(library.recents.count, UserLibrary.recentsLimit)
        XCTAssertEqual(library.recents.count, 50)
        XCTAssertEqual(library.recents.first?.string, "char-59")
        XCTAssertEqual(library.recents.last?.string, "char-10")
        XCTAssertFalse(library.recents.contains { $0.string == "char-9" })
    }

    func testClearRecentsKeepsFavourites() {
        var library = UserLibrary()
        library.seedIfNeeded(seed)
        library.recordUse(LibraryItem(string: "\u{1F600}", name: "grinning face"))

        library.clearRecents()

        XCTAssertTrue(library.recents.isEmpty)
        XCTAssertEqual(library.favourites, seed)
    }

    // MARK: - Exact scalar identity

    func testLibraryItemEqualityUsesExactScalars() {
        XCTAssertEqual(LibraryItem(string: "\u{C5}", name: "A"), LibraryItem(string: "\u{C5}", name: "A"))
        XCTAssertNotEqual(LibraryItem(string: "\u{C5}", name: "A"), LibraryItem(string: "\u{212B}", name: "A"))
        XCTAssertNotEqual(LibraryItem(string: "\u{C5}", name: "A"), LibraryItem(string: "\u{C5}", name: "B"))
    }

    func testAngstromSignAndAWithRingAreDistinctInFavouritesAndRecents() {
        // Swift's String equality folds these together; the library must not.
        XCTAssertEqual("\u{C5}", "\u{212B}")
        XCTAssertFalse("\u{C5}".isExactly("\u{212B}"))

        var library = UserLibrary()
        library.seedIfNeeded([
            LibraryItem(string: "\u{C5}", name: "a with ring"),
            LibraryItem(string: "\u{212B}", name: "angstrom sign")
        ])
        XCTAssertEqual(library.favourites.count, 2)
        XCTAssertTrue(library.isFavourite("\u{C5}"))
        XCTAssertTrue(library.isFavourite("\u{212B}"))

        library.removeFavourite("\u{C5}")
        XCTAssertEqual(library.favourites.map(\.string), ["\u{212B}"])

        library.recordUse(LibraryItem(string: "\u{C5}", name: "a with ring"))
        library.recordUse(LibraryItem(string: "\u{212B}", name: "angstrom sign"))
        XCTAssertEqual(library.recents.count, 2)
        XCTAssertEqual(library.recents.map(\.string), ["\u{212B}", "\u{C5}"])
    }

    func testHeartWithAndWithoutVariationSelectorAreDistinct() {
        XCTAssertFalse("\u{2764}".isExactly("\u{2764}\u{FE0F}"))

        var library = UserLibrary()
        library.seedIfNeeded([
            LibraryItem(string: "\u{2764}", name: "heart"),
            LibraryItem(string: "\u{2764}\u{FE0F}", name: "heart with VS16")
        ])
        XCTAssertEqual(library.favourites.count, 2)

        library.removeFavourite("\u{2764}")
        XCTAssertEqual(library.favourites.map(\.string), ["\u{2764}\u{FE0F}"])

        library.recordUse(LibraryItem(string: "\u{2764}", name: "heart"))
        library.recordUse(LibraryItem(string: "\u{2764}\u{FE0F}", name: "heart with VS16"))
        XCTAssertEqual(library.recents.count, 2)
    }

    func testFavouritesUnknownToAnyCatalogueArePreservedUntouched() throws {
        let unknown = [
            LibraryItem(string: "\u{10FFFF}", name: "unassigned"),
            LibraryItem(string: "A\u{30A}", name: "decomposed a")
        ]
        var library = UserLibrary()
        library.seedIfNeeded(unknown)

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(UserLibrary.self, from: data)

        XCTAssertEqual(decoded.favourites, unknown)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        var library = UserLibrary()
        library.seedIfNeeded(seed)
        library.toggleFavourite(LibraryItem(string: "\u{1F600}", name: "grinning face"))
        library.recordUse(LibraryItem(string: "\u{2192}", name: "right arrow"))
        library.recordUse(LibraryItem(string: "\u{1F44D}", name: "thumbs up"))

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(UserLibrary.self, from: data)

        XCTAssertEqual(decoded, library)
    }

    func testDecodingWithoutIsSeededInfersItFromFavourites() throws {
        let withFavourites = """
        {"schemaVersion":1,"favourites":[{"string":"k","name":"K"}],"recents":[]}
        """
        let decoded = try JSONDecoder().decode(UserLibrary.self, from: Data(withFavourites.utf8))
        XCTAssertTrue(decoded.isSeeded)

        let withoutFavourites = """
        {"schemaVersion":1,"favourites":[],"recents":[]}
        """
        let empty = try JSONDecoder().decode(UserLibrary.self, from: Data(withoutFavourites.utf8))
        XCTAssertFalse(empty.isSeeded)
    }

    func testDecodingIgnoresUnknownKeys() throws {
        let json = """
        {"schemaVersion":1,"favourites":[{"string":"k","name":"K","future":true}],"recents":[],"isSeeded":true,"future":"value"}
        """
        let decoded = try JSONDecoder().decode(UserLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.favourites, [LibraryItem(string: "k", name: "K")])
        XCTAssertTrue(decoded.isSeeded)
    }
}
