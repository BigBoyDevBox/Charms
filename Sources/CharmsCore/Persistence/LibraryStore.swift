import Foundation

/// Reads and writes `UserLibrary` as JSON in a directory.
///
/// This store is not thread-safe. Use it from one serial context; the app
/// calls it from the main actor, and a concurrent save while a load is in
/// flight would race on `library.json` and on the pending migration state.
public final class LibraryStore {
    /// What `load()` found on disk.
    public enum LoadOutcome: Equatable {
        /// The file was read and understood.
        case loaded
        /// There was no library file.
        case missing
        /// The file was unreadable or undecodable and was moved aside.
        case recoveredCorrupt(preservedAt: URL)
        /// The file uses a newer schema, so it was moved aside untouched.
        case newerSchema(version: Int, preservedAt: URL)
    }

    /// Errors thrown by `save`.
    public enum LibraryStoreError: Error, Equatable, CustomStringConvertible {
        case encodingFailed(reason: String)
        case directoryCreationFailed(path: String, reason: String)
        case writeFailed(path: String, reason: String)
        case replaceFailed(path: String, reason: String)
        case preservationFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case .encodingFailed(let reason):
                return "could not encode the library: \(reason)"
            case .directoryCreationFailed(let path, let reason):
                return "could not create directory at \(path): \(reason)"
            case .writeFailed(let path, let reason):
                return "could not write \(path): \(reason)"
            case .replaceFailed(let path, let reason):
                return "could not replace \(path): \(reason)"
            case .preservationFailed(let path, let reason):
                return "could not preserve \(path): \(reason)"
            }
        }
    }

    private let directory: URL
    private let fileManager: FileManager
    private let fileURL: URL

    /// Original bytes and version of a file that `load()` migrated. The next
    /// `save` copies them aside so pre-migration data is never lost.
    private var pendingPreMigration: (version: Int, data: Data)?

    /// - Parameters:
    ///   - directory: Directory that contains `library.json`. Created on the
    ///     first save.
    ///   - fileManager: File manager used for every disk operation.
    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.fileURL = directory.appendingPathComponent("library.json")
    }

    // MARK: - Loading

    public func load() -> (library: UserLibrary, outcome: LoadOutcome) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return (UserLibrary(), .missing)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // Unreadable files cannot be interpreted or copied, so moving
            // them aside is the recovery.
            let preserved = preserveAside(baseName: "library.corrupt.json") ?? fileURL
            return (UserLibrary(), .recoveredCorrupt(preservedAt: preserved))
        }

        // Read only the schema version first. A newer file must not be
        // interpreted by the current model, and a missing version marks a
        // pre-schema file that migration handles.
        let probe: SchemaProbe
        do {
            probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        } catch {
            let preserved = preserveAside(baseName: "library.corrupt.json") ?? fileURL
            return (UserLibrary(), .recoveredCorrupt(preservedAt: preserved))
        }

        if let version = probe.schemaVersion, version > UserLibrary.currentSchemaVersion {
            let name = "library.schema-\(version).json"
            let preserved = preserveAside(baseName: name) ?? fileURL
            return (UserLibrary(), .newerSchema(version: version, preservedAt: preserved))
        }

        let library: UserLibrary
        do {
            library = try JSONDecoder().decode(UserLibrary.self, from: data)
        } catch {
            let preserved = preserveAside(baseName: "library.corrupt.json") ?? fileURL
            return (UserLibrary(), .recoveredCorrupt(preservedAt: preserved))
        }

        guard library.schemaVersion < UserLibrary.currentSchemaVersion else {
            return (library, .loaded)
        }

        pendingPreMigration = (library.schemaVersion, data)
        return (Self.migrate(library, from: library.schemaVersion), .loaded)
    }

    // MARK: - Saving

    /// Writes the library as pretty-printed JSON with sorted keys.
    ///
    /// The data goes to a temporary file in the same directory first and then
    /// replaces `library.json`, so an interrupted write leaves the previous
    /// file intact. The directory is created when needed.
    public func save(_ library: UserLibrary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data: Data
        do {
            data = try encoder.encode(library)
        } catch {
            throw LibraryStoreError.encodingFailed(reason: error.localizedDescription)
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LibraryStoreError.directoryCreationFailed(path: directory.path, reason: error.localizedDescription)
        }

        if let pending = pendingPreMigration {
            let name = "library.pre-migration-v\(pending.version).json"
            let destination = uniqueURL(for: directory.appendingPathComponent(name))
            do {
                try pending.data.write(to: destination, options: .atomic)
            } catch {
                throw LibraryStoreError.preservationFailed(path: destination.path, reason: error.localizedDescription)
            }
            pendingPreMigration = nil
        }

        let temporaryURL = directory.appendingPathComponent("library.json.tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
        } catch {
            throw LibraryStoreError.writeFailed(path: temporaryURL.path, reason: error.localizedDescription)
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            throw LibraryStoreError.replaceFailed(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    // MARK: - Private

    /// Moves the current library file aside under `baseName`, choosing a
    /// fresh name when that one is already taken. Returns nil when the move
    /// fails, in which case the file is still at `fileURL`.
    private func preserveAside(baseName: String) -> URL? {
        let destination = uniqueURL(for: directory.appendingPathComponent(baseName))
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// `url` when it is free, otherwise the first free `-2`, `-3`, ...
    /// sibling with the same extension.
    private func uniqueURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2
        while true {
            let candidate = parent.appendingPathComponent("\(stem)-\(counter)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    /// The single place to add structural upgrades for older schemas. Schema
    /// 1 is the first versioned schema, so today the whole migration is the
    /// version stamp below; a future schema bump adds its transformation
    /// here, oldest version first.
    private static func migrate(_ library: UserLibrary, from version: Int) -> UserLibrary {
        var migrated = library
        migrated.schemaVersion = UserLibrary.currentSchemaVersion
        return migrated
    }

    /// Minimal decode used to inspect the schema version without applying
    /// the current model to a file that may have a newer shape.
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int?
    }
}
