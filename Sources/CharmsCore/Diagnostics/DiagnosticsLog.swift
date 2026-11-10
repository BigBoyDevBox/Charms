import Foundation

/// A small in-memory record of what Charms did, kept so that a problem can
/// be described in a bug report.
///
/// Entries hold only categories, counts and timings chosen from fixed
/// vocabularies. There is no free-form text field, so typed text, queries,
/// document contents, window titles and clipboard contents cannot end up
/// here even by mistake. Nothing is written to disk until the user exports
/// it, and nothing is ever sent anywhere.
public final class DiagnosticsLog: @unchecked Sendable {
    public enum Category: String, Sendable, CaseIterable {
        case launch
        case invocation
        case capture
        case placement
        case session
        case insertion
        case trigger
        case permission
        case hotKey
        case storage
    }

    public struct Entry: Equatable, Sendable {
        public let timestamp: Date
        public let category: Category
        /// A short code from the reporting component's own vocabulary.
        public let code: String
        /// Bundle identifier of the application concerned, when relevant.
        public let application: String?
        public let milliseconds: Double?
    }

    public static let capacity = 400

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let now: @Sendable () -> Date
    private let sink: (@Sendable (Entry) -> Void)?

    /// `sink` additionally receives every entry as it is recorded. The app
    /// uses it to trace a development run on standard error.
    public init(now: @escaping @Sendable () -> Date = { Date() }, sink: (@Sendable (Entry) -> Void)? = nil) {
        self.now = now
        self.sink = sink
    }

    /// Records an event. `code` must be a fixed identifier such as
    /// `placed-caret`; codes with anything but lowercase letters, digits,
    /// dots and hyphens are rejected, which keeps user text out by design.
    public func record(_ category: Category, _ code: String, application: String? = nil, milliseconds: Double? = nil) {
        guard Self.isCode(code) else { return }
        let entry = Entry(
            timestamp: now(),
            category: category,
            code: code,
            application: application.flatMap { Self.isBundleIdentifier($0) ? $0 : nil },
            milliseconds: milliseconds
        )
        lock.lock()
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        lock.unlock()
        sink?(entry)
    }

    public var snapshot: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    /// The export file: a header describing the system, then one line per
    /// entry.
    public func export(header: [(String, String)]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["Charms diagnostics", "Contains timings and categories only. No typed text, queries or clipboard contents.", ""]
        for (key, value) in header {
            lines.append("\(key): \(value)")
        }
        lines.append("")
        for entry in snapshot {
            lines.append("\(formatter.string(from: entry.timestamp))\t\(Self.describe(entry))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One entry without its time: category, code, and the optional fields.
    public static func describe(_ entry: Entry) -> String {
        var line = "\(entry.category.rawValue)\t\(entry.code)"
        if let application = entry.application {
            line += "\tapp=\(application)"
        }
        if let milliseconds = entry.milliseconds {
            line += "\tms=\(String(format: "%.1f", milliseconds))"
        }
        return line
    }

    static func isCode(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 48 else { return false }
        return text.utf8.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
        }
    }

    static func isBundleIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 155 else { return false }
        return text.utf8.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "_")
        }
    }
}
