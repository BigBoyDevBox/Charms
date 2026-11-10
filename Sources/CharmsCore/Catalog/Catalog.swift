import Foundation

/// Emoji skin-tone preference. `none` keeps the default yellow form.
public enum SkinTone: String, Sendable, CaseIterable, Codable {
    case none
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    /// The Fitzpatrick modifier scalar, or nil for `none`.
    public var modifier: UInt32? {
        switch self {
        case .none: return nil
        case .light: return 0x1F3FB
        case .mediumLight: return 0x1F3FC
        case .medium: return 0x1F3FD
        case .mediumDark: return 0x1F3FE
        case .dark: return 0x1F3FF
        }
    }

    public static func isModifier(_ value: UInt32) -> Bool {
        value >= 0x1F3FB && value <= 0x1F3FF
    }
}

/// The immutable bundled catalogue.
///
/// Entries keep their file order, which the generator chose deliberately, so
/// an index is a stable handle for the lifetime of one loaded catalogue.
/// Persisted data never stores indices; it stores exact strings.
public final class Catalog: Sendable {
    public let header: CatalogFormat.Header
    public let entries: [CatalogEntry]
    public let ranges: [CodePointRange]

    private let indexByString: [ExactString: Int]
    /// For a variant, the index of its base emoji. Empty slot is -1.
    private let baseOfVariant: [Int32]
    /// For a base emoji, the indices of its variants, which follow it directly.
    private let variantsOfBase: [Int: Range<Int>]

    public static let empty = Catalog(contents: CatalogFormat.Contents(
        header: CatalogFormat.Header(unicodeVersion: "", emojiVersion: "", cldrVersion: ""),
        entries: [],
        ranges: []
    ))

    public init(contents: CatalogFormat.Contents) {
        header = contents.header
        entries = contents.entries
        ranges = contents.ranges.sorted { $0.first < $1.first }

        var byString: [ExactString: Int] = [:]
        byString.reserveCapacity(contents.entries.count)
        var bases = [Int32](repeating: -1, count: contents.entries.count)
        var variants: [Int: Range<Int>] = [:]
        var currentBase: Int?
        for (index, entry) in contents.entries.enumerated() {
            // The first occurrence wins, so a duplicated sequence can never
            // shadow the entry the generator listed first.
            if byString[entry.string.exact] == nil {
                byString[entry.string.exact] = index
            }
            switch entry.kind {
            case .emoji:
                currentBase = index
            case .variant:
                guard let base = currentBase else { continue }
                bases[index] = Int32(base)
                let existing = variants[base]
                variants[base] = (existing?.lowerBound ?? index)..<(index + 1)
            default:
                currentBase = nil
            }
        }
        indexByString = byString
        baseOfVariant = bases
        variantsOfBase = variants
    }

    public convenience init(data: Data) throws {
        self.init(contents: try CatalogFormat.decode(data))
    }

    // MARK: - Lookup

    public func index(of string: String) -> Int? {
        indexByString[string.exact]
    }

    /// Resolves an exact string to its entry: a listed entry, or a synthetic
    /// one for a single character inside an algorithmically named range.
    public func resolve(_ string: String) -> CatalogEntry? {
        if let index = index(of: string) {
            return entries[index]
        }
        var scalars = string.unicodeScalars.makeIterator()
        guard let only = scalars.next(), scalars.next() == nil else { return nil }
        return rangeEntry(for: only.value)
    }

    /// The entry for a code point that lives in an algorithmically named range.
    public func rangeEntry(for value: UInt32) -> CatalogEntry? {
        guard let scalar = Unicode.Scalar(value), let range = range(containing: value) else { return nil }
        return CatalogEntry(
            string: String(scalar),
            kind: .letter,
            rank: CatalogEntry.Rank.rare,
            age: range.age,
            group: range.group,
            name: range.name(for: value)
        )
    }

    private func range(containing value: UInt32) -> CodePointRange? {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = ranges[middle]
            if value < candidate.first {
                high = middle - 1
            } else if value > candidate.last {
                low = middle + 1
            } else {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Variants

    /// Indices of the skin-tone variants of a base emoji, in catalogue order.
    public func variants(ofEntryAt index: Int) -> Range<Int>? {
        variantsOfBase[index]
    }

    /// The base emoji of a variant entry.
    public func base(ofVariantAt index: Int) -> Int? {
        guard index >= 0, index < baseOfVariant.count else { return nil }
        let base = baseOfVariant[index]
        return base >= 0 ? Int(base) : nil
    }

    /// The variant of a base emoji in which every person uses `tone`, when the
    /// emoji data defines one. Never manufactures a sequence.
    public func variant(ofEntryAt index: Int, tone: SkinTone) -> Int? {
        guard let modifier = tone.modifier, let variants = variantsOfBase[index] else { return nil }
        return variants.first { candidate in
            let modifiers = entries[candidate].string.unicodeScalars.lazy
                .map(\.value)
                .filter(SkinTone.isModifier)
            return !modifiers.isEmpty && modifiers.allSatisfy { $0 == modifier }
        }
    }

    /// The entry to offer for `index` under a skin-tone preference: the toned
    /// variant when one exists, otherwise the entry itself.
    public func preferredIndex(for index: Int, tone: SkinTone) -> Int {
        variant(ofEntryAt: index, tone: tone) ?? index
    }
}
