import XCTest
@testable import CharmsCatalogBuilder
import CharmsCore

/// Builds the catalogue from the repository's real `Data/` directory and
/// checks it against the Unicode and Emoji data itself. The expected values
/// come from the sources and the specification, not from builder output.
final class IntegrationTests: XCTestCase {
    /// The repository root: `Tests/CharmsCatalogBuilderTests` is two levels
    /// below it.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var cached: CatalogBuildResult?

    private var result: CatalogBuildResult {
        get throws {
            if let cached = Self.cached { return cached }
            let built = try CatalogBuilder.build(
                CatalogSources(directory: Self.root.appendingPathComponent("Data")))
            Self.cached = built
            return built
        }
    }

    private var catalog: Catalog {
        get throws { Catalog(contents: try result.contents) }
    }

    private func entry(_ scalars: [UInt32]) throws -> CatalogEntry? {
        var view = String.UnicodeScalarView()
        for value in scalars {
            guard let scalar = Unicode.Scalar(value) else { return nil }
            view.append(scalar)
        }
        return try catalog.index(of: String(view)).map { try catalog.entries[$0] }
    }

    private func scalars(of entry: CatalogEntry) -> [UInt32] {
        entry.string.unicodeScalars.map(\.value)
    }

    // MARK: - Whole-catalogue properties

    func testCatalogueRoundTripsThroughTheFormat() throws {
        let contents = try result.contents
        let decoded = try CatalogFormat.decode(Data(try CatalogFormat.encode(contents).utf8))
        XCTAssertEqual(decoded, contents)
    }

    func testTwoBuildsAreByteIdentical() throws {
        let first = try CatalogFormat.encode(result.contents)
        let second = try CatalogFormat.encode(CatalogBuilder.build(
            CatalogSources(directory: Self.root.appendingPathComponent("Data"))).contents)
        XCTAssertEqual(Data(first.utf8), Data(second.utf8))
    }

    func testCommittedCatalogueMatchesAFreshBuild() throws {
        let onDisk = try Data(
            contentsOf: Self.root.appendingPathComponent("Resources/catalog.txt"))
        XCTAssertEqual(onDisk, Data(try CatalogFormat.encode(result.contents).utf8))
    }

    func testHeaderVersionsComeFromTheSourceHeaders() throws {
        let header = try result.contents.header
        XCTAssertEqual(header.unicodeVersion, "18.0.0")
        XCTAssertEqual(header.emojiVersion, "18.0")
        XCTAssertEqual(header.cldrVersion, "49")
    }

    // MARK: - Individual entries

    func testRightwardsArrowHasCuratedAliases() throws {
        let arrow = try XCTUnwrap(try entry([0x2192]))
        XCTAssertEqual(arrow.kind, .symbol)
        XCTAssertEqual(arrow.rank, 0)
        XCTAssertTrue(arrow.aliases.contains(CatalogAlias(text: "->", rank: 0)))
        XCTAssertTrue(arrow.aliases.contains(CatalogAlias(text: "arrow", rank: 0)))
    }

    func testThumbsUpHasFiveVariantsInToneOrder() throws {
        let catalog = try catalog
        let base = try XCTUnwrap(try entry([0x1F44D]))
        XCTAssertEqual(base.kind, .emoji)
        let index = try XCTUnwrap(catalog.index(of: base.string))
        let variantIndices = try XCTUnwrap(catalog.variants(ofEntryAt: index))
        XCTAssertEqual(variantIndices.count, 5)
        let tones = variantIndices.map { scalars(of: catalog.entries[$0]) }
        XCTAssertEqual(tones, [
            [0x1F44D, 0x1F3FB], [0x1F44D, 0x1F3FC], [0x1F44D, 0x1F3FD],
            [0x1F44D, 0x1F3FE], [0x1F44D, 0x1F3FF],
        ])
        XCTAssertTrue(variantIndices.allSatisfy { catalog.entries[$0].kind == .variant })
    }

    func testWomanTechnologistHasFiveVariants() throws {
        let catalog = try catalog
        let base = try XCTUnwrap(try entry([0x1F469, 0x200D, 0x1F4BB]))
        XCTAssertEqual(base.kind, .emoji)
        let index = try XCTUnwrap(catalog.index(of: base.string))
        XCTAssertEqual(catalog.variants(ofEntryAt: index)?.count, 5)
    }

    func testScotlandFlagAndKeycapExist() throws {
        let flag = try XCTUnwrap(try entry(
            [0x1F3F4, 0xE0067, 0xE0062, 0xE0073, 0xE0063, 0xE0074, 0xE007F]))
        XCTAssertEqual(flag.kind, .emoji)
        let keycap = try XCTUnwrap(try entry([0x0023, 0xFE0F, 0x20E3]))
        XCTAssertEqual(keycap.kind, .emoji)
    }

    func testTextAndEmojiHeartsAreSeparateEntries() throws {
        let text = try XCTUnwrap(try entry([0x2764]))
        let emoji = try XCTUnwrap(try entry([0x2764, 0xFE0F]))
        XCTAssertEqual(text.kind, .symbol)
        XCTAssertEqual(emoji.kind, .emoji)
    }

    func testCanonicallyEquivalentEntriesStayDistinct() throws {
        let angstrom = try XCTUnwrap(try entry([0x212B]))
        let aRing = try XCTUnwrap(try entry([0x00C5]))
        XCTAssertEqual(angstrom.name, "angstrom sign")
        XCTAssertEqual(aRing.name, "latin capital letter a with ring above")

        let ohm = try XCTUnwrap(try entry([0x2126]))
        let omega = try XCTUnwrap(try entry([0x03A9]))
        XCTAssertEqual(ohm.name, "ohm sign")
        XCTAssertEqual(omega.name, "greek capital letter omega")
    }

    func testAppleLogoExtraIsPresent() throws {
        let logo = try XCTUnwrap(try entry([0xF8FF]))
        XCTAssertEqual(logo.name, "apple logo")
    }

    func testExcludedCodePointsAreNotEntries() throws {
        XCTAssertNil(try entry([0x1F3FB]), "skin tone component alone")
        XCTAssertNil(try entry([0xE000]), "private use")
        XCTAssertNil(try entry([0xFE0F]), "variation selector")
        XCTAssertNil(try entry([0x1F1E6]), "regional indicator")
    }

    // MARK: - Algorithmically named ranges

    func testRangeResolution() throws {
        let catalog = try catalog
        XCTAssertNil(try entry([0x4E2D]), "CJK ideographs are not listed entries")
        XCTAssertEqual(catalog.resolve("\u{4E2D}")?.name, "cjk unified ideograph-4e2d")
        XCTAssertEqual(catalog.resolve("\u{D55C}")?.name, "hangul syllable han")
    }

    // MARK: - Spaces

    func testFormatCharactersAreSpaces() throws {
        XCTAssertEqual(try XCTUnwrap(try entry([0x00A0])).kind, .space)
        XCTAssertEqual(try XCTUnwrap(try entry([0x200D])).kind, .space)
        XCTAssertEqual(try XCTUnwrap(try entry([0xFEFF])).kind, .space)
    }

    // MARK: - Statistics

    func testStatisticsMatchTheSources() throws {
        let statistics = try result.statistics
        XCTAssertLessThanOrEqual(statistics.maxUTF16Length, 20)
        XCTAssertEqual(statistics.longestEntry.utf16.count, statistics.maxUTF16Length)
        // emoji-test.txt's fully-qualified rows split into bases and variants.
        let emojiText = try String(
            contentsOf: Self.root.appendingPathComponent("Data/unicode/18.0.0/emoji-test.txt"),
            encoding: .utf8)
        let fullyQualified = try EmojiTestParser.parse(emojiText).fullyQualified.count
        XCTAssertEqual(statistics.emojiBases + statistics.variants, fullyQualified)
        XCTAssertEqual(statistics.totalEntries, try result.contents.entries.count)
        XCTAssertEqual(statistics.rangeCount, try result.contents.ranges.count)
    }
}
