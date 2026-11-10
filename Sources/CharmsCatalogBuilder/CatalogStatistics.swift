import Foundation

/// Deterministic build statistics, written next to the catalogue as
/// `catalog-manifest.json`. No timestamps, so two builds of the same sources
/// produce identical bytes.
public struct CatalogStatistics: Codable, Equatable, Sendable {
    public var unicodeVersion: String
    public var emojiVersion: String
    public var cldrVersion: String
    public var totalEntries: Int
    /// Entry counts keyed by kind name (`emoji`, `variant`, `symbol`, ...).
    public var entriesByKind: [String: Int]
    /// Entry counts keyed by rank (`0` through `4`).
    public var entriesByRank: [String: Int]
    public var rangeCount: Int
    /// Total code points covered by all ranges.
    public var rangeCodePoints: Int
    public var emojiBases: Int
    public var variants: Int
    /// Longest entry string measured in UTF-16 units.
    public var maxUTF16Length: Int
    /// The entry whose string reaches `maxUTF16Length`.
    public var longestEntry: String
    /// Entries whose display name comes from a CLDR `tts` annotation.
    public var entriesWithCldrNames: Int
    /// Alias lines read from `aliases.tsv`.
    public var curatedAliases: Int
    /// Entries carrying at least one curated alias.
    public var entriesWithAliases: Int
    /// UTF-8 byte count of the encoded catalogue.
    public var outputBytes: Int

    public init(
        unicodeVersion: String, emojiVersion: String, cldrVersion: String,
        totalEntries: Int, entriesByKind: [String: Int], entriesByRank: [String: Int],
        rangeCount: Int, rangeCodePoints: Int, emojiBases: Int, variants: Int,
        maxUTF16Length: Int, longestEntry: String,
        entriesWithCldrNames: Int, curatedAliases: Int, entriesWithAliases: Int,
        outputBytes: Int
    ) {
        self.unicodeVersion = unicodeVersion
        self.emojiVersion = emojiVersion
        self.cldrVersion = cldrVersion
        self.totalEntries = totalEntries
        self.entriesByKind = entriesByKind
        self.entriesByRank = entriesByRank
        self.rangeCount = rangeCount
        self.rangeCodePoints = rangeCodePoints
        self.emojiBases = emojiBases
        self.variants = variants
        self.maxUTF16Length = maxUTF16Length
        self.longestEntry = longestEntry
        self.entriesWithCldrNames = entriesWithCldrNames
        self.curatedAliases = curatedAliases
        self.entriesWithAliases = entriesWithAliases
        self.outputBytes = outputBytes
    }
}
