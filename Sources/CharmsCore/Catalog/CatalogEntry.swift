import Foundation

/// A Unicode or Emoji version such as 15.1, used to decide whether the running
/// system can be expected to draw an entry.
public struct UnicodeAge: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: UInt8
    public let minor: UInt8

    public init(major: UInt8, minor: UInt8) {
        self.major = major
        self.minor = minor
    }

    /// Parses `"15.1"` or `"15"`. Returns nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, let major = UInt8(parts[0]) else { return nil }
        let minor: UInt8
        if parts.count == 2 {
            guard let parsed = UInt8(parts[1]) else { return nil }
            minor = parsed
        } else {
            minor = 0
        }
        self.init(major: major, minor: minor)
    }

    public static func < (lhs: UnicodeAge, rhs: UnicodeAge) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    public var description: String { "\(major).\(minor)" }
}

/// A curated familiar name for an entry, such as `->` or `cmd`.
///
/// `rank` orders the entries that share one alias: rank 0 is the entry a
/// person most likely means, so `arrow` lists → before ⇒.
public struct CatalogAlias: Hashable, Sendable {
    public let text: String
    public let rank: UInt8

    public init(text: String, rank: UInt8) {
        self.text = text
        self.rank = rank
    }
}

/// One insertable item: a single character or a complete emoji sequence.
public struct CatalogEntry: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// A fully-qualified emoji shown in ordinary results.
        case emoji
        /// A skin-tone variant of the nearest preceding `emoji` entry. Reached
        /// through that entry, by literal lookup, or by code point.
        case variant
        case symbol
        case punctuation
        case letter
        case number
        /// Combining marks, previewed on a dotted circle.
        case mark
        /// Spaces and invisible formatting characters that are useful to insert.
        case space
    }

    /// Lower ranks are more prominent when relevance is otherwise equal.
    public enum Rank {
        public static let curated: UInt8 = 0
        public static let common: UInt8 = 1
        public static let symbol: UInt8 = 2
        public static let script: UInt8 = 3
        public static let rare: UInt8 = 4
        public static let maximum: UInt8 = 9
    }

    /// The exact text inserted for this entry.
    public let string: String
    public let kind: Kind
    public let rank: UInt8
    /// Emoji version for emoji and variants, Unicode age otherwise.
    public let age: UnicodeAge
    /// Emoji group and subgroup (`Smileys & Emotion/face-smiling`) or the
    /// Unicode block name (`Arrows`).
    public let group: String
    /// Lowercase display name, for example `right arrow`.
    public let name: String
    /// Extra lowercase search phrases: CLDR keywords, the formal Unicode name
    /// when `name` differs from it, and formal name aliases.
    public let keywords: [String]
    public let aliases: [CatalogAlias]

    public init(
        string: String,
        kind: Kind,
        rank: UInt8,
        age: UnicodeAge,
        group: String,
        name: String,
        keywords: [String] = [],
        aliases: [CatalogAlias] = []
    ) {
        self.string = string
        self.kind = kind
        self.rank = rank
        self.age = age
        self.group = group
        self.name = name
        self.keywords = keywords
        self.aliases = aliases
    }

    public static func == (lhs: CatalogEntry, rhs: CatalogEntry) -> Bool {
        lhs.string.isExactly(rhs.string)
            && lhs.kind == rhs.kind
            && lhs.rank == rhs.rank
            && lhs.age == rhs.age
            && lhs.group == rhs.group
            && lhs.name == rhs.name
            && lhs.keywords == rhs.keywords
            && lhs.aliases == rhs.aliases
    }

    /// The name with its first letter capitalised, as shown in the footer.
    public var displayName: String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    public var isEmoji: Bool { kind == .emoji || kind == .variant }
}

/// A block of characters whose names follow a rule instead of being listed
/// one by one, such as the CJK unified ideographs. These stay reachable by
/// literal character and by code point without holding tens of thousands of
/// names in memory.
public struct CodePointRange: Sendable, Equatable {
    public enum NameRule: Sendable, Equatable {
        /// The name is `prefix` followed by the code point in hex.
        case hexSuffix(prefix: String)
        /// The name is composed from the jamo short names.
        case hangulSyllable
    }

    public let first: UInt32
    public let last: UInt32
    public let rule: NameRule
    public let group: String
    public let age: UnicodeAge

    public init(first: UInt32, last: UInt32, rule: NameRule, group: String, age: UnicodeAge) {
        self.first = first
        self.last = last
        self.rule = rule
        self.group = group
        self.age = age
    }

    public func contains(_ value: UInt32) -> Bool {
        value >= first && value <= last
    }

    /// Lowercase name of a code point inside this range.
    public func name(for value: UInt32) -> String {
        switch rule {
        case .hexSuffix(let prefix):
            return (prefix + CodePoint.hex(value)).lowercased()
        case .hangulSyllable:
            return HangulSyllable.name(for: value).lowercased()
        }
    }
}

enum HangulSyllable {
    private static let base: UInt32 = 0xAC00
    private static let vowelCount: UInt32 = 21
    private static let trailCount: UInt32 = 28
    private static let leads = ["G", "GG", "N", "D", "DD", "R", "M", "B", "BB", "S", "SS", "", "J", "JJ", "C", "K", "T", "P", "H"]
    private static let vowels = ["A", "AE", "YA", "YAE", "EO", "E", "YEO", "YE", "O", "WA", "WAE", "OE", "YO", "U", "WEO", "WE", "WI", "YU", "EU", "YI", "I"]
    private static let trails = ["", "G", "GG", "GS", "N", "NJ", "NH", "D", "L", "LG", "LM", "LB", "LS", "LT", "LP", "LH", "M", "B", "BS", "S", "SS", "NG", "J", "C", "K", "T", "P", "H"]

    /// The Unicode Standard's algorithmic Hangul syllable name (section 3.12).
    static func name(for value: UInt32) -> String {
        let offset = value - base
        let lead = Int(offset / (vowelCount * trailCount))
        let vowel = Int((offset % (vowelCount * trailCount)) / trailCount)
        let trail = Int(offset % trailCount)
        guard lead < leads.count else { return "HANGUL SYLLABLE" }
        return "HANGUL SYLLABLE " + leads[lead] + vowels[vowel] + trails[trail]
    }
}
