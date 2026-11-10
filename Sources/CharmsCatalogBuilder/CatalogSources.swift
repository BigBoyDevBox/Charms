import Foundation

/// The pinned source files a catalogue build reads, laid out as in `Data/`:
/// `unicode/18.0.0/` for the UCD and emoji files, `cldr/49/` for the CLDR
/// JSON, and `aliases.tsv` plus `extras.tsv` at the top level.
public struct CatalogSources {
    public var unicodeData: String
    public var nameAliases: String
    public var blocks: String
    public var scripts: String
    public var derivedAge: String
    public var emojiTest: String
    public var annotations: Data
    public var annotationsDerived: Data
    public var aliases: String
    public var extras: String

    public init(
        unicodeData: String,
        nameAliases: String,
        blocks: String,
        scripts: String,
        derivedAge: String,
        emojiTest: String,
        annotations: Data,
        annotationsDerived: Data,
        aliases: String,
        extras: String
    ) {
        self.unicodeData = unicodeData
        self.nameAliases = nameAliases
        self.blocks = blocks
        self.scripts = scripts
        self.derivedAge = derivedAge
        self.emojiTest = emojiTest
        self.annotations = annotations
        self.annotationsDerived = annotationsDerived
        self.aliases = aliases
        self.extras = extras
    }

    /// Loads the files from a `Data` directory laid out like the repository's.
    public init(directory: URL) throws {
        func file(_ path: String) throws -> String {
            let url = directory.appendingPathComponent(path)
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw CatalogError.unreadableFile(path: url.path, reason: error.localizedDescription)
            }
        }
        func data(_ path: String) throws -> Data {
            let url = directory.appendingPathComponent(path)
            do {
                return try Data(contentsOf: url)
            } catch {
                throw CatalogError.unreadableFile(path: url.path, reason: error.localizedDescription)
            }
        }
        let ucd = "unicode/18.0.0"
        let cldr = "cldr/\(CldrAnnotations.fallbackVersion)"
        self.init(
            unicodeData: try file("\(ucd)/UnicodeData.txt"),
            nameAliases: try file("\(ucd)/NameAliases.txt"),
            blocks: try file("\(ucd)/Blocks.txt"),
            scripts: try file("\(ucd)/Scripts.txt"),
            derivedAge: try file("\(ucd)/DerivedAge.txt"),
            emojiTest: try file("\(ucd)/emoji-test.txt"),
            annotations: try data("\(cldr)/annotations-en.json"),
            annotationsDerived: try data("\(cldr)/annotations-derived-en.json"),
            aliases: try file("aliases.tsv"),
            extras: try file("extras.tsv")
        )
    }
}
