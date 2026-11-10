import XCTest
@testable import CharmsCore

final class LibraryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: LibraryStore!
    private var fileManager: FileManager { .default }

    override func setUp() {
        super.setUp()
        directory = fileManager.temporaryDirectory.appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)")
        store = LibraryStore(directory: directory)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: directory)
        store = nil
        directory = nil
        super.tearDown()
    }

    private var libraryURL: URL { directory.appendingPathComponent("library.json") }

    private func writeLibraryData(_ data: Data) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: libraryURL)
    }

    private func makeLibrary() -> UserLibrary {
        var library = UserLibrary()
        library.seedIfNeeded([
            LibraryItem(string: "\u{2192}", name: "right arrow"),
            LibraryItem(string: "\u{1F44D}", name: "thumbs up")
        ])
        library.recordUse(LibraryItem(string: "\u{2764}", name: "heart"))
        return library
    }

    // MARK: - Loading

    func testMissingFileReturnsEmptyLibrary() {
        let result = store.load()
        XCTAssertEqual(result.outcome, .missing)
        XCTAssertEqual(result.library, UserLibrary())
    }

    func testSaveThenLoadRoundTrip() throws {
        let library = makeLibrary()
        try store.save(library)
        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.library, library)
    }

    func testSavedJSONHasSortedKeysAndIsStableAcrossSaves() throws {
        let library = makeLibrary()
        try store.save(library)
        let first = try Data(contentsOf: libraryURL)
        try store.save(library)
        let second = try Data(contentsOf: libraryURL)
        XCTAssertEqual(first, second)

        let text = String(decoding: first, as: UTF8.self)
        guard let favourites = text.range(of: "\"favourites\""),
              let isSeeded = text.range(of: "\"isSeeded\""),
              let recents = text.range(of: "\"recents\""),
              let schemaVersion = text.range(of: "\"schemaVersion\"") else {
            return XCTFail("saved JSON is missing expected keys")
        }
        XCTAssertLessThan(favourites.lowerBound, isSeeded.lowerBound)
        XCTAssertLessThan(isSeeded.lowerBound, recents.lowerBound)
        XCTAssertLessThan(recents.lowerBound, schemaVersion.lowerBound)
    }

    func testCorruptFileIsPreservedByteForByteAndFreshLibraryReturned() throws {
        let bytes = Data("definitely not json".utf8)
        try writeLibraryData(bytes)
        let result = store.load()
        guard case .recoveredCorrupt(let preservedAt) = result.outcome else {
            return XCTFail("expected recoveredCorrupt, got \(result.outcome)")
        }
        XCTAssertEqual(result.library, UserLibrary())
        XCTAssertEqual(try Data(contentsOf: preservedAt), bytes)
        XCTAssertFalse(fileManager.fileExists(atPath: libraryURL.path))
    }

    func testSecondCorruptRecoveryDoesNotOverwriteFirstPreservedFile() throws {
        let firstBytes = Data("first corrupt payload".utf8)
        try writeLibraryData(firstBytes)
        guard case .recoveredCorrupt(let firstURL) = store.load().outcome else {
            return XCTFail("expected recoveredCorrupt for the first file")
        }

        let secondBytes = Data("second corrupt payload".utf8)
        try writeLibraryData(secondBytes)
        guard case .recoveredCorrupt(let secondURL) = store.load().outcome else {
            return XCTFail("expected recoveredCorrupt for the second file")
        }

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
    }

    func testNewerSchemaIsPreservedAndNotInterpreted() throws {
        let newerVersion = UserLibrary.currentSchemaVersion + 4
        let json = """
        {"schemaVersion": \(newerVersion), "favourites": [{"string":"z","name":"Z"}], "recents": [], "isSeeded": true}
        """
        try writeLibraryData(Data(json.utf8))
        let result = store.load()
        guard case .newerSchema(let version, let preservedAt) = result.outcome else {
            return XCTFail("expected newerSchema, got \(result.outcome)")
        }
        XCTAssertEqual(version, newerVersion)
        XCTAssertEqual(result.library, UserLibrary())
        XCTAssertEqual(try Data(contentsOf: preservedAt), Data(json.utf8))
        XCTAssertFalse(fileManager.fileExists(atPath: libraryURL.path))
    }

    func testLeftoverTemporaryFileDoesNotAffectLoad() throws {
        let library = makeLibrary()
        try store.save(library)
        let temporaryURL = directory.appendingPathComponent("library.json.tmp")
        try Data("interrupted write".utf8).write(to: temporaryURL)
        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.library, library)
    }

    func testOlderSchemaIsMigratedAndOriginalPreservedOnNextSave() throws {
        let json = """
        {"schemaVersion": 0, "favourites": [{"string":"k","name":"K"}], "recents": [], "isSeeded": true}
        """
        try writeLibraryData(Data(json.utf8))
        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.library.schemaVersion, UserLibrary.currentSchemaVersion)
        XCTAssertEqual(result.library.favourites.map(\.string), ["k"])

        try store.save(result.library)

        let preservedURL = directory.appendingPathComponent("library.pre-migration-v0.json")
        XCTAssertTrue(fileManager.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), Data(json.utf8))
        XCTAssertTrue(fileManager.fileExists(atPath: libraryURL.path))
    }

    func testMissingSchemaVersionIsMigratedAsVersionZero() throws {
        let json = """
        {"favourites": [{"string":"k","name":"K"}], "recents": []}
        """
        try writeLibraryData(Data(json.utf8))
        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.library.schemaVersion, UserLibrary.currentSchemaVersion)
        XCTAssertTrue(result.library.isSeeded)

        try store.save(result.library)

        let preservedURL = directory.appendingPathComponent("library.pre-migration-v0.json")
        XCTAssertTrue(fileManager.fileExists(atPath: preservedURL.path))
    }

    // MARK: - Saving

    func testSaveCreatesDirectory() throws {
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        try store.save(makeLibrary())
        XCTAssertTrue(fileManager.fileExists(atPath: directory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: libraryURL.path))
    }

    func testSaveIntoPathThatCannotBeCreatedThrows() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let badStore = LibraryStore(directory: blocker)
        XCTAssertThrowsError(try badStore.save(makeLibrary()))
    }
}
