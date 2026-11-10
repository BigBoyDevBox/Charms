import AppKit
import CharmsCore
import CoreText

/// Decides whether this system can draw a catalogue entry.
///
/// The bundled data is newer than any system's emoji font, so the question
/// is asked of the running system instead of a version table. Measured on
/// macOS 27: a supported emoji, however long its sequence, is laid out with
/// the advance of one emoji in one glyph, or in two overlaid glyphs for a
/// couple with two skin tones. An unsupported sequence falls apart into its
/// parts and takes the advance of several, and an unknown character is
/// drawn from the last-resort font. Asking a font whether it has glyphs for
/// the code points cannot tell these apart, since the parts all exist.
@MainActor
final class GlyphSupport {
    private var cache: [ExactString: Bool] = [:]
    private let font = NSFont.systemFont(ofSize: 24)
    private lazy var emojiAdvance: Double = advance(of: "\u{1F600}").width

    func isSupported(_ entry: CatalogEntry) -> Bool {
        // Spaces and invisible format characters have nothing to draw.
        if entry.kind == .space { return true }
        let key = ExactString(entry.string)
        if let known = cache[key] { return known }
        let result = measure(entry)
        cache[key] = result
        return result
    }

    private func measure(_ entry: CatalogEntry) -> Bool {
        let layout = advance(of: entry.string)
        if layout.usesLastResort || layout.glyphs == 0 { return false }
        guard entry.isEmoji else { return true }
        return layout.glyphs <= 2 && layout.width <= emojiAdvance * 1.25
    }

    private func advance(of string: String) -> (width: Double, glyphs: Int, usesLastResort: Bool) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        var glyphs = 0
        var usesLastResort = false
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            glyphs += CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            if let runFont = attributes[kCTFontAttributeName as String] {
                // The attribute is always a CTFont; the cast cannot fail.
                let name = CTFontCopyPostScriptName(runFont as! CTFont) as String
                if name == "LastResort" { usesLastResort = true }
            }
        }
        return (width, glyphs, usesLastResort)
    }
}
