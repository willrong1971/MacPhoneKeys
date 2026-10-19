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

func shadowedFill(_ path: NSBezierPath, fill: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 27, 91, alpha: 0.22)
    shadow.shadowBlurRadius = 13
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    fill.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawArtwork() {
    let tile = rounded(NSRect(x: 80, y: 80, width: 864, height: 864), radius: 196)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    tileShadow.shadowBlurRadius = 32
    tileShadow.shadowOffset = NSSize(width: 0, height: -13)
    tileShadow.set()
    color(20, 92, 225).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(9, 67, 187), ending: color(44, 129, 250))!
        .draw(in: tile, angle: 65)
    let edge = rounded(NSRect(x: 82, y: 82, width: 860, height: 860), radius: 194)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    edge.lineWidth = 3
    edge.stroke()

    // The generous key shapes and single space bar remain distinct at small sizes.
    let white = color(246, 250, 255)
    shadowedFill(rounded(NSRect(x: 176, y: 270, width: 484, height: 300), radius: 43), fill: white)
    let keyColor = color(39, 109, 226)
    keyColor.setFill()
    for y: CGFloat in [466, 400] {
        for column in 0..<7 {
            rounded(NSRect(x: 211 + CGFloat(column) * 61, y: y, width: 46, height: 46), radius: 9).fill()
        }
    }
    rounded(NSRect(x: 211, y: 334, width: 46, height: 46), radius: 9).fill()
    rounded(NSRect(x: 272, y: 334, width: 291, height: 46), radius: 9).fill()
    rounded(NSRect(x: 577, y: 334, width: 46, height: 46), radius: 9).fill()

    // A blank blue screen and two broad inset details identify the phone without
    // miniature text, labels, logos or decorative UI.
    shadowedFill(rounded(NSRect(x: 660, y: 300, width: 194, height: 430), radius: 44), fill: white)
    let screen = rounded(NSRect(x: 678, y: 322, width: 158, height: 386), radius: 28)
    NSGradient(starting: color(25, 89, 210), ending: color(38, 115, 235))!
        .draw(in: screen, angle: 90)
    white.setFill()
    rounded(NSRect(x: 722, y: 681, width: 69, height: 11), radius: 5.5).fill()
    rounded(NSRect(x: 720, y: 340, width: 73, height: 9), radius: 4.5).fill()

    // An open, simple Bluetooth connection mark balances the two device shapes.
    let connection = NSBezierPath()
    connection.move(to: NSPoint(x: 447, y: 610))
    connection.line(to: NSPoint(x: 447, y: 790))
    connection.line(to: NSPoint(x: 507, y: 742))
    connection.line(to: NSPoint(x: 387, y: 658))
    connection.move(to: NSPoint(x: 387, y: 742))
    connection.line(to: NSPoint(x: 507, y: 658))
    connection.line(to: NSPoint(x: 447, y: 610))
    connection.lineWidth = 17
    connection.lineCapStyle = .round
    connection.lineJoinStyle = .round
    white.setStroke()
    connection.stroke()
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
    drawArtwork()
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
