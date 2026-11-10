import Foundation
import CharmsCore

/// A sorted table of code point spans carrying a value, shared by
/// `Blocks.txt`, `Scripts.txt` and `DerivedAge.txt`, which all use the line
/// format `FIRST[..LAST] ; value`.
struct RangeTable<Value> {
    struct Span {
        let first: UInt32
        let last: UInt32
        let value: Value
    }

    /// Spans in file order. The Unicode files list them sorted by first
    /// code point; `value(for:)` relies on that.
    let spans: [Span]

    func value(for codePoint: UInt32) -> Value? {
        var low = 0
        var high = spans.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let span = spans[middle]
            if codePoint < span.first {
                high = middle - 1
            } else if codePoint > span.last {
                low = middle + 1
            } else {
                return span.value
            }
        }
        return nil
    }
}

enum RangeTableParser {
    /// Parses `<span> ; <value>` rows. The value text passes through `convert`
    /// so each caller validates its own column. A comment suffix (` # ...`) is
    /// removed first.
    static func parse<Value>(_ text: String, file: String,
                             convert: (Substring, Int) throws -> Value) throws -> RangeTable<Value> {
        var spans: [RangeTable<Value>.Span] = []
        for line in SourceParsing.dataLines(text) {
            let body = line.text.split(separator: "#", maxSplits: 1)[0]
            let fields = body.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 2 else {
                throw CatalogError.malformed(file: file, line: line.number,
                                             reason: "expected '<first>[..<last>] ; <value>'")
            }
            let bounds = SourceParsing.trimmed(fields[0]).components(separatedBy: "..")
            let first = try SourceParsing.hex(Substring(bounds[0]), file: file, line: line.number)
            let last: UInt32
            switch bounds.count {
            case 1:
                last = first
            case 2:
                last = try SourceParsing.hex(Substring(bounds[1]), file: file, line: line.number)
            default:
                throw CatalogError.malformed(file: file, line: line.number, reason: "invalid code point range")
            }
            guard first <= last else {
                throw CatalogError.malformed(file: file, line: line.number, reason: "range end precedes its start")
            }
            spans.append(.init(first: first, last: last,
                               value: try convert(SourceParsing.trimmed(fields[1]), line.number)))
        }
        // Scripts.txt groups rows by script rather than by code point, so a
        // sorted copy is required for the binary-search lookup.
        return RangeTable(spans: spans.sorted { $0.first < $1.first })
    }
}
