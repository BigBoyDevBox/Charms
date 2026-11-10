import Foundation
import CharmsCore
import CharmsCatalogBuilder

// CharmsCatalogTool generate: builds the catalogue from Data/ and writes
// Resources/catalog.txt plus Resources/catalog-manifest.json.
// CharmsCatalogTool check: rebuilds and compares both committed files
// byte-for-byte with a fresh build.

enum Tool {
    static let usage = """
        usage: CharmsCatalogTool generate [--data DIR] [--output FILE] [--manifest FILE]
               CharmsCatalogTool check [--data DIR] [--output FILE] [--manifest FILE]
        """

    static func main() -> Int {
        var arguments = CommandLine.arguments.dropFirst()
        guard let command = arguments.popFirst(), command == "generate" || command == "check" else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return 2
        }

        var dataDirectory = "Data"
        var output = "Resources/catalog.txt"
        var manifest = "Resources/catalog-manifest.json"
        while let argument = arguments.popFirst() {
            guard let value = arguments.popFirst() else {
                FileHandle.standardError.write(Data((usage + "\n").utf8))
                return 2
            }
            switch argument {
            case "--data": dataDirectory = value
            case "--output": output = value
            case "--manifest": manifest = value
            default:
                FileHandle.standardError.write(Data((usage + "\n").utf8))
                return 2
            }
        }

        do {
            let result = try CatalogBuilder.build(CatalogSources(directory: URL(fileURLWithPath: dataDirectory)))
            let catalogue = try CatalogFormat.encode(result.contents)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestText = String(decoding: try encoder.encode(result.statistics), as: UTF8.self) + "\n"

            switch command {
            case "generate":
                try write(catalogue, to: output)
                try write(manifestText, to: manifest)
                print("wrote \(output) (\(catalogue.utf8.count) bytes) and \(manifest)")
                print("\(result.statistics.totalEntries) entries, \(result.statistics.emojiBases) emoji bases, "
                    + "\(result.statistics.variants) variants, \(result.statistics.rangeCount) ranges")
            case "check":
                var mismatched: [String] = []
                if read(output) != catalogue { mismatched.append(output) }
                if read(manifest) != manifestText { mismatched.append(manifest) }
                guard mismatched.isEmpty else {
                    FileHandle.standardError.write(Data(
                        ("stale: " + mismatched.joined(separator: ", ")
                         + " differ from a fresh build; run `CharmsCatalogTool generate`\n").utf8))
                    return 1
                }
                print("ok: \(output) and \(manifest) match a fresh build")
            default:
                break
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data(("error: \(error)\n").utf8))
            return 1
        }
    }

    static func write(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func read(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }
}

exit(Int32(Tool.main()))
