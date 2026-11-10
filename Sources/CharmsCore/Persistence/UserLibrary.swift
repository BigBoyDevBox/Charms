import Foundation

/// One entry in the user's library: the exact text to insert and a snapshot
/// of the display name it had when the entry was saved.
///
/// The name is a snapshot because a later catalogue may no longer list the
/// string, and the library must still be able to show a label for it.
public struct LibraryItem: Codable, Sendable, Equatable {
    /// The exact text inserted for this item.
    public var string: String
    /// Display name captured when the item was saved.
    public var name: String

    public init(string: String, name: String) {
        self.string = string
        self.name = name
    }

    /// Identity is the exact scalar sequence of `string`; `name` compares
    /// normally. Swift's `String ==` would treat `"\u{212B}"` and `"\u{C5}"`
    /// as equal, but they insert different text.
    public static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.string.isExactly(rhs.string) && lhs.name == rhs.name
    }
}

/// The user's favourites and recents.
///
/// Favourites keep the user's explicit order. Recents are most recent first
/// and capped at `recentsLimit`. Every comparison of an item's `string` uses
/// exact scalars, so canonically equivalent characters stay distinct.
public struct UserLibrary: Codable, Sendable, Equatable {
    /// The schema version this build writes and reads.
    public static let currentSchemaVersion = 1
    /// Maximum number of recents kept; the oldest entries are dropped.
    public static let recentsLimit = 50

    public var schemaVersion: Int
    /// Explicit user order.
    public var favourites: [LibraryItem]
    /// Most recent first.
    public var recents: [LibraryItem]
    /// True once the first-run seed has been applied. Seeding never happens
    /// twice, so clearing every favourite stays cleared.
    public var isSeeded: Bool

    /// An empty, unseeded library at the current schema version.
    public init() {
        self.schemaVersion = UserLibrary.currentSchemaVersion
        self.favourites = []
        self.recents = []
        self.isSeeded = false
    }

    // MARK: - Seeding

    /// Applies `seed` only on the first call. Once seeded, later calls are
    /// ignored, so removing the last favourite leaves the list empty on
    /// purpose; `resetFavourites(to:)` is the explicit way back to the seed.
    public mutating func seedIfNeeded(_ seed: [LibraryItem]) {
        guard !isSeeded else { return }
        favourites = Self.deduplicated(seed)
        isSeeded = true
    }

    // MARK: - Favourites

    public func isFavourite(_ string: String) -> Bool {
        favourites.contains { $0.string.isExactly(string) }
    }

    /// Adds `item` at the end when it is not a favourite, otherwise removes
    /// the favourite with the same exact string. Returns true when the item
    /// is now a favourite.
    @discardableResult
    public mutating func toggleFavourite(_ item: LibraryItem) -> Bool {
        guard let index = favourites.firstIndex(where: { $0.string.isExactly(item.string) }) else {
            favourites.append(item)
            return true
        }
        favourites.remove(at: index)
        return false
    }

    public mutating func removeFavourite(_ string: String) {
        favourites.removeAll { $0.string.isExactly(string) }
    }

    /// Moves the favourite with the exact `string` by `offset` positions,
    /// negative for left and positive for right, clamped to both ends.
    /// Returns false when the item is absent or already at the boundary.
    @discardableResult
    public mutating func moveFavourite(_ string: String, by offset: Int) -> Bool {
        guard let index = favourites.firstIndex(where: { $0.string.isExactly(string) }) else { return false }
        let target = max(0, min(favourites.count - 1, index + offset))
        guard target != index else { return false }
        let item = favourites.remove(at: index)
        favourites.insert(item, at: target)
        return true
    }

    /// Replaces favourites with the deduplicated seed. Recents are untouched.
    public mutating func resetFavourites(to seed: [LibraryItem]) {
        favourites = Self.deduplicated(seed)
    }

    public mutating func clearFavourites() {
        favourites = []
    }

    // MARK: - Recents

    /// Records a use: removes any recent with the same exact string, inserts
    /// `item` at the front, and trims to `recentsLimit`.
    public mutating func recordUse(_ item: LibraryItem) {
        recents.removeAll { $0.string.isExactly(item.string) }
        recents.insert(item, at: 0)
        if recents.count > Self.recentsLimit {
            recents.removeLast(recents.count - Self.recentsLimit)
        }
    }

    /// Empties recents and leaves favourites alone.
    public mutating func clearRecents() {
        recents = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, favourites, recents, isSeeded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing version marks a pre-schema file. Migration treats it as
        // version 0, the oldest schema.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        favourites = try container.decode([LibraryItem].self, forKey: .favourites)
        recents = try container.decode([LibraryItem].self, forKey: .recents)
        // Files written before the seed flag existed are seeded exactly when
        // they already carry favourites.
        isSeeded = try container.decodeIfPresent(Bool.self, forKey: .isSeeded) ?? !favourites.isEmpty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(favourites, forKey: .favourites)
        try container.encode(recents, forKey: .recents)
        try container.encode(isSeeded, forKey: .isSeeded)
    }

    // MARK: - Helpers

    /// First occurrence of each exact string wins.
    private static func deduplicated(_ items: [LibraryItem]) -> [LibraryItem] {
        var result: [LibraryItem] = []
        result.reserveCapacity(items.count)
        for item in items where !result.contains(where: { $0.string.isExactly(item.string) }) {
            result.append(item)
        }
        return result
    }
}
