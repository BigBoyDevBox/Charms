import Foundation
import CharmsCore

/// CLDR English names and keywords for one annotated string.
struct CldrAnnotation {
    /// The `default` keyword list.
    let keywords: [String]
    /// The single `tts` name, when present.
    let tts: String?
}

/// Merged English annotations: `annotations/en` first, then
/// `annotationsDerived/en` for the sequences the base file does not cover.
/// Keys are exact strings with no U+FE0F, so lookups strip U+FE0F too.
struct CldrAnnotations {
    private let map: [ExactString: CldrAnnotation]

    /// The CLDR release: a `version` field in either file when present, else
    /// the pinned path component `49` from `Data/cldr/49/`.
    let version: String

    static let fallbackVersion = "49"

    init(map: [ExactString: CldrAnnotation], version: String) {
        self.map = map
        self.version = version
    }

    /// The annotation whose key is `string` minus every U+FE0F.
    func annotation(for string: String) -> CldrAnnotation? {
        map[ExactString(String(string.unicodeScalars.filter { $0.value != 0xFE0F }))]
    }
}

enum CldrAnnotationsParser {
    private struct Document {
        let map: [ExactString: CldrAnnotation]
        let version: String?
    }

    static func parse(annotations: Data, annotationsFile: String,
                      derived: Data, derivedFile: String) throws -> CldrAnnotations {
        let base = try parseDocument(annotations, rootKey: "annotations", file: annotationsFile)
        let derived = try parseDocument(derived, rootKey: "annotationsDerived", file: derivedFile)
        var map = base.map
        for (key, value) in derived.map where map[key] == nil {
            map[key] = value
        }
        let version = base.version ?? derived.version ?? CldrAnnotations.fallbackVersion
        return CldrAnnotations(map: map, version: version)
    }

    private static func parseDocument(_ data: Data, rootKey: String, file: String) throws -> Document {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CatalogError.invalidStructure(file: file, reason: "not valid JSON: \(error.localizedDescription)")
        }
        guard let root = object as? [String: Any], let section = root[rootKey] as? [String: Any] else {
            throw CatalogError.invalidStructure(file: file, reason: "missing top-level key '\(rootKey)'")
        }
        guard let entries = section["annotations"] as? [String: Any] else {
            throw CatalogError.invalidStructure(file: file, reason: "missing '\(rootKey).annotations' map")
        }

        var map: [ExactString: CldrAnnotation] = [:]
        map.reserveCapacity(entries.count)
        for (key, raw) in entries {
            guard let fields = raw as? [String: Any] else {
                throw CatalogError.invalidStructure(file: file, reason: "annotation for '\(key)' is not an object")
            }
            map[key.exact] = CldrAnnotation(
                keywords: try stringList(fields["default"], key: key, field: "default", file: file) ?? [],
                tts: try stringList(fields["tts"], key: key, field: "tts", file: file)?.first
            )
        }

        var version = section["version"] as? String
        if version == nil, let identity = section["identity"] as? [String: Any] {
            version = (identity["version"] as? [String: Any])?["_cldrVersion"] as? String
                ?? identity["version"] as? String
        }
        return Document(map: map, version: version)
    }

    private static func stringList(_ raw: Any?, key: String, field: String, file: String) throws -> [String]? {
        guard let raw else { return nil }
        guard let list = raw as? [Any] else {
            throw CatalogError.invalidStructure(file: file, reason: "field '\(field)' for '\(key)' is not an array")
        }
        return try list.map { element in
            guard let text = element as? String else {
                throw CatalogError.invalidStructure(file: file, reason: "field '\(field)' for '\(key)' contains a non-string")
            }
            return text
        }
    }
}
