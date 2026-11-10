// Generates assets/Charms-icon.png, the committed 1024x1024 master that
// scripts/make-icon.swift turns into the .iconset at build time.
//
//   swift media-sources/icon.swift media-sources/icon.png assets/Charms-icon.png
//
// The artwork in media-sources/icon.png is a square, opaque, edge-to-edge
// image; it is kept as delivered and never edited. A macOS app icon is not
// edge to edge: it is a rounded tile of 824 points on a 1024 point canvas,
// with a soft shadow beneath it. This script places the artwork on that grid.
// Rerun it after replacing the artwork, and commit the result.
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("icon.swift: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: icon.swift ARTWORK_PNG OUTPUT_PNG") }

let artworkURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read \(artworkURL.path)")
}
guard artwork.width == artwork.height else {
    fail("the artwork must be square, got \(artwork.width) x \(artwork.height)")
}

/// The canvas every macOS icon size is resampled from.
let canvasSide = 1024
/// The tile on Apple's macOS icon grid: 824 of 1024 points, centred.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
/// The grid's corner radius for that tile.
let tileCornerRadius: CGFloat = 185.4

guard artwork.width >= Int(tile.width) else {
    fail("the artwork must be at least \(Int(tile.width)) pixels wide, got \(artwork.width)")
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: canvasSide, height: canvasSide, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("cannot create a bitmap context") }

// The system's icon shape has continuous corners, not circular arcs. SwiftUI
// is the one public source of that curve.
let tilePath = RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous).path(in: tile).cgPath

// The shadow is cast by an opaque tile, which the artwork then covers.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -10), blur: 20,
    color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.3])!
)
context.addPath(tilePath)
context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
context.interpolationQuality = .high
context.draw(artwork, in: tile)
context.restoreGState()

guard let image = context.makeImage() else { fail("cannot render the image") }
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fail("cannot write \(outputURL.path)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot finish \(outputURL.path)") }
print("Wrote \(outputURL.path)")
