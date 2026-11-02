#!/usr/bin/env swift
import AppKit
import Foundation

// Original geometric artwork. Rebuild from the repository root with:
//   xcrun swift scripts/generate-icon.swift
// Optional first argument: an alternate Resources output directory.
// All coordinates use a 1024-point, bottom-left-origin canvas. Every icon size is
// drawn directly from these paths rather than resampling a raster master.

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : projectRoot.appendingPathComponent("Resources", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

// One sculpted key with phone proportions. The Return mark belongs to its face,
// so the symbol stays a single object at Finder and menu-bar sizes.
func drawArtwork(backingScale: CGFloat) {
    let tile = rounded(NSRect(x: 80, y: 80, width: 864, height: 864), radius: 196)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    // NSShadow uses device-space distances, unlike the scaled vector paths.
    tileShadow.shadowBlurRadius = 30 * backingScale
    tileShadow.shadowOffset = NSSize(width: 0, height: -12 * backingScale)
    tileShadow.set()
    color(25, 85, 208).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colorsAndLocations:
        (color(29, 64, 182), 0),
        (color(29, 105, 232), 0.52),
        (color(69, 161, 250), 1))!.draw(in: tile, angle: 70)
    let edge = rounded(NSRect(x: 82, y: 82, width: 860, height: 860), radius: 194)
    NSColor.white.withAlphaComponent(0.20).setStroke()
    edge.lineWidth = 3
    edge.stroke()

    // The shallow lower lip makes this a physical keyboard key; the tall face
    // and inset speaker make the same silhouette read as a phone.
    let base = rounded(NSRect(x: 282, y: 204, width: 460, height: 590), radius: 108)
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow()
    keyShadow.shadowColor = color(7, 30, 105, alpha: 0.32)
    keyShadow.shadowBlurRadius = 28 * backingScale
    keyShadow.shadowOffset = NSSize(width: 0, height: -20 * backingScale)
    keyShadow.set()
    color(179, 207, 247).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()

    let face = rounded(NSRect(x: 282, y: 232, width: 460, height: 574), radius: 108)
    NSGradient(starting: color(228, 239, 255), ending: color(255, 255, 255))!
        .draw(in: face, angle: 90)
    NSColor.white.withAlphaComponent(0.85).setStroke()
    face.lineWidth = 3
    face.stroke()

    let ink = color(27, 96, 214)
    ink.setFill()
    rounded(NSRect(x: 450, y: 718, width: 124, height: 26), radius: 13).fill()

    let returnMark = NSBezierPath()
    returnMark.move(to: NSPoint(x: 638, y: 615))
    returnMark.line(to: NSPoint(x: 638, y: 495))
    returnMark.curve(to: NSPoint(x: 604, y: 461),
                     controlPoint1: NSPoint(x: 638, y: 472),
                     controlPoint2: NSPoint(x: 627, y: 461))
    returnMark.line(to: NSPoint(x: 398, y: 461))
    returnMark.move(to: NSPoint(x: 471, y: 534))
    returnMark.line(to: NSPoint(x: 398, y: 461))
    returnMark.line(to: NSPoint(x: 471, y: 388))
    returnMark.lineWidth = 48
    returnMark.lineCapStyle = .round
    returnMark.lineJoinStyle = .round
    ink.setStroke()
    returnMark.stroke()
}

func renderPNG(pixels: Int, at destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB,
                                       bytesPerRow: pixels * 4, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not allocate the icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.cgContext.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawArtwork(backingScale: scale)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon PNG")
    }
    try data.write(to: destination, options: .atomic)
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in sizes {
    try renderPNG(pixels: pixels, at: iconset.appendingPathComponent(name))
}
try renderPNG(pixels: 1024, at: output.appendingPathComponent("AppIcon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Created \(output.appendingPathComponent("AppIcon.png").path)")
print("Created \(output.appendingPathComponent("AppIcon.icns").path)")
