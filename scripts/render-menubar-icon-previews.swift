import AppKit

/// Build and run without launching MacPhoneKeys or creating Bluetooth managers:
/// xcrun swiftc Sources/MenuBarIcon.swift scripts/render-menubar-icon-previews.swift \
///   -framework AppKit -o build/render-menubar-icon-previews
/// build/render-menubar-icon-previews [output-directory]
@main
enum MenuBarIconPreviews {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/icon-previews",
                         isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scale in [1, 2] {
            for active in [false, true] {
                let bitmap = glyph(active: active, color: .black, scale: scale)
                try save(bitmap, at: output.appendingPathComponent("\(active ? "active" : "inactive")-\(scale)x.png"))
            }
            try save(contactSheet(scale: scale), at: output.appendingPathComponent("contact-\(scale)x.png"))
        }
        print(output.path)
    }

    private static func bitmap(size: NSSize, scale: Int, drawing: () -> Void) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: Int(size.width) * scale,
                                      pixelsHigh: Int(size.height) * scale,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        // The bitmap's point size already supplies the backing-scale transform.
        drawing()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func glyph(active: Bool, color: NSColor, scale: Int) -> NSBitmapImageRep {
        bitmap(size: NSSize(width: 28, height: 20), scale: scale) {
            let bounds = NSRect(x: 0, y: 0, width: 28, height: 20)
            MenuBarIcon.image(active: active).draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
        }
    }

    private static func contactSheet(scale: Int) -> NSBitmapImageRep {
        bitmap(size: NSSize(width: 640, height: 340), scale: scale) {
            for dark in [false, true] {
                let origin: CGFloat = dark ? 320 : 0
                let foreground: NSColor = dark ? .white : .black
                (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)).setFill()
                NSBezierPath(rect: NSRect(x: origin, y: 0, width: 320, height: 340)).fill()
                label(dark ? "Dark menu bar" : "Light menu bar", x: origin + 20, y: 305,
                      color: foreground, size: 15)
                label("Actual size · 38 pt status item", x: origin + 20, y: 278,
                      color: foreground.withAlphaComponent(0.75), size: 11)

                for active in [false, true] {
                    let column: CGFloat = active ? 170 : 20
                    let alpha: CGFloat = active ? 1 : 0.75
                    let color = foreground.withAlphaComponent(alpha)
                    let image = NSImage(size: NSSize(width: 28, height: 20))
                    image.addRepresentation(glyph(active: active, color: color, scale: 10))
                    image.draw(in: NSRect(x: origin + column + 5, y: 241, width: 28, height: 20))
                    label(active ? "Active" : "Inactive · 75%", x: origin + column, y: 219,
                          color: foreground, size: 11)
                    image.draw(in: NSRect(x: origin + column, y: 80, width: 140, height: 100))
                }
                label("5× detail · transparent template mask", x: origin + 20, y: 42,
                      color: foreground.withAlphaComponent(0.75), size: 11)
            }
        }
    }

    private static func label(_ text: String, x: CGFloat, y: CGFloat, color: NSColor, size: CGFloat) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color
        ])
    }

    private static func save(_ bitmap: NSBitmapImageRep, at url: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MenuBarIconPreviews", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
        }
        try data.write(to: url)
    }
}
