import Foundation

/// Errors thrown while building the catalogue.
///
/// Line-based source files report the file name and the 1-based line number so
/// a malformed row can be found without guessing. Structural problems that can
/// be enumerated, such as unresolved aliases, are collected and thrown once so
/// every violation is visible in a single run.
public enum CatalogError: Error, CustomStringConvertible {
    /// A line in a source file does not match the documented format.
    case malformed(file: String, line: Int, reason: String)
    /// A required file is missing or unreadable.
    case unreadableFile(path: String, reason: String)
    /// A JSON source does not have the documented shape.
    case invalidStructure(file: String, reason: String)
    /// One or more cross-file violations; every element is one problem.
    case invalid([String])

    public var description: String {
        switch self {
        case .malformed(let file, let line, let reason):
            return "\(file):\(line): \(reason)"
        case .unreadableFile(let path, let reason):
            return "\(path): \(reason)"
        case .invalidStructure(let file, let reason):
            return "\(file): \(reason)"
        case .invalid(let problems):
            return problems.joined(separator: "\n")
        }
    }
}
