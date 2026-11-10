import CharmsCore
import Combine
import Foundation

/// Favourites and recents, loaded once and saved after every change.
@MainActor
final class LibraryController: ObservableObject {
    @Published private(set) var library: UserLibrary

    private let store: LibraryStore
    private let diagnostics: DiagnosticsLog

    init(paths: AppPaths, diagnostics: DiagnosticsLog) {
        self.diagnostics = diagnostics
        store = LibraryStore(directory: paths.supportDirectory)
        let loaded = store.load()
        library = loaded.library
        switch loaded.outcome {
        case .loaded: diagnostics.record(.storage, "library-loaded")
        case .missing: diagnostics.record(.storage, "library-missing")
        case .recoveredCorrupt: diagnostics.record(.storage, "library-corrupt-preserved")
        case .newerSchema: diagnostics.record(.storage, "library-newer-schema-preserved")
        }
    }

    /// Applies the first-run favourites once the catalogue can name them.
    func seedIfNeeded(from catalog: Catalog) {
        guard !library.isSeeded else { return }
        let seed = SeedFavourites.items(in: catalog)
        guard !seed.isEmpty else { return }
        change { $0.seedIfNeeded(seed) }
    }

    func change(_ mutate: (inout UserLibrary) -> Void) {
        var copy = library
        mutate(&copy)
        guard copy != library else { return }
        library = copy
        do {
            try store.save(copy)
        } catch {
            // The change stays in memory; the next change tries again.
            diagnostics.record(.storage, "library-save-failed")
        }
    }
}
