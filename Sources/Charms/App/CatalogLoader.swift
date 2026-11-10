import CharmsCore
import Foundation

/// Finds and reads the bundled character catalogue.
enum CatalogLoader {
    struct Loaded: Sendable {
        let catalog: Catalog
        let index: SearchIndex
        let milliseconds: Double
    }

    /// The catalogue inside the app bundle, or, for a binary run straight
    /// from the package during development, the one in the repository.
    static func locate() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CHARMS_CATALOG"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("catalog.txt"))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/catalog.txt"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reads and indexes the catalogue away from the main thread, so the
    /// first use of the keyboard never waits for it.
    static func load() async -> Loaded? {
        guard let url = locate() else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Loaded? in
            let start = Date()
            guard let data = try? Data(contentsOf: url), let catalog = try? Catalog(data: data) else { return nil }
            let index = SearchIndex(catalog: catalog)
            return Loaded(catalog: catalog, index: index, milliseconds: Date().timeIntervalSince(start) * 1000)
        }.value
    }
}
