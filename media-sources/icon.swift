// Generates assets/Charms-icon.png, the committed 1024x1024 master that
// scripts/make-icon.swift turns into the .iconset at build time.
//
//   swift media-sources/icon.swift assets/Charms-icon.png
//
// The motif is the picker itself: a small grid of character cells on a dark
// tile, with one cell selected. It is drawn with CoreGraphics and CoreText
// from system fonts only, so the icon is reproducible from this file.
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: icon.swift OUTPUT_PNG\n".utf8))
    exit(1)
}

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("error: cannot create a bitmap context\n".utf8))
    exit(1)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red / 255, green / 255, blue / 255, alpha])!
}

// The tile: the standard macOS icon shape, inset from the canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0, 0, 0, 0.32))
context.addPath(tilePath)
context.setFillColor(color(34, 30, 64))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(74, 58, 150), color(38, 30, 84), color(22, 18, 48)] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
context.restoreGState()

// A 2 x 2 grid of cells. The lower right one is the selection.
let glyphs = ["→", "∞", "✓", "★"]
let cellSize: CGFloat = 300
let gap: CGFloat = 44
let gridSide = cellSize * 2 + gap
let gridOrigin = CGPoint(x: tile.midX - gridSide / 2, y: tile.midY - gridSide / 2)
let selected = 3

func drawGlyph(_ glyph: String, in rect: CGRect, fill: CGColor) {
    let font = CTFontCreateUIFontForLanguage(.system, 190, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 190, nil)
    let bold = CTFontCreateCopyWithSymbolicTraits(font, 190, nil, .traitBold, .traitBold) ?? font
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): bold,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attributes))
    // Centre on the ink, not on the advance, so every symbol sits in the
    // middle of its cell whatever its side bearings.
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(x: rect.midX - ink.midX, y: rect.midY - ink.midY)
    CTLineDraw(line, context)
}

for (index, glyph) in glyphs.enumerated() {
    let column = CGFloat(index % 2)
    let row = CGFloat(index / 2)
    // Row 0 is the top row; CoreGraphics counts upwards.
    let rect = CGRect(
        x: gridOrigin.x + column * (cellSize + gap),
        y: gridOrigin.y + (1 - row) * (cellSize + gap),
        width: cellSize, height: cellSize
    )
    let path = CGPath(roundedRect: rect, cornerWidth: 64, cornerHeight: 64, transform: nil)
    context.addPath(path)
    if index == selected {
        context.setFillColor(color(255, 196, 61))
        context.fillPath()
        drawGlyph(glyph, in: rect, fill: color(40, 30, 80))
    } else {
        context.setFillColor(color(255, 255, 255, 0.11))
        context.fillPath()
        drawGlyph(glyph, in: rect, fill: color(244, 242, 255))
    }
}

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("error: cannot render the image\n".utf8))
    exit(1)
}
let url = URL(fileURLWithPath: arguments[1])
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("error: cannot write \(url.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: cannot finish \(url.path)\n".utf8))
    exit(1)
}
print("Wrote \(url.path)")
