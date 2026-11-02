import AppKit

/// A single phone-shaped input key, matching the app icon.
/// Fixed black artwork with white linework; the status item dims it when idle.
enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 20), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.setFill()

            let key = roundedRect(NSRect(x: 6.5, y: 1.25, width: 15, height: 17.5), radius: 4)
            let speaker = roundedRect(NSRect(x: 12, y: 15.3, width: 4, height: 1.25), radius: 0.625)
            let returnMark = NSBezierPath()
            returnMark.move(to: NSPoint(x: 18, y: 12.4))
            returnMark.line(to: NSPoint(x: 16.3, y: 12.4))
            returnMark.line(to: NSPoint(x: 16.3, y: 9.2))
            returnMark.line(to: NSPoint(x: 12.2, y: 9.2))
            returnMark.line(to: NSPoint(x: 13.75, y: 10.75))
            returnMark.line(to: NSPoint(x: 12.55, y: 11.95))
            returnMark.line(to: NSPoint(x: 9, y: 8.4))
            returnMark.line(to: NSPoint(x: 12.55, y: 4.85))
            returnMark.line(to: NSPoint(x: 13.75, y: 6.05))
            returnMark.line(to: NSPoint(x: 12.2, y: 7.6))
            returnMark.line(to: NSPoint(x: 16.5, y: 7.6))
            returnMark.curve(to: NSPoint(x: 18, y: 9.1),
                             controlPoint1: NSPoint(x: 17.5, y: 7.6),
                             controlPoint2: NSPoint(x: 18, y: 8.1))
            returnMark.close()

            key.fill()
            let lineColor = NSColor(calibratedWhite: active ? 1 : 0.62, alpha: 1)
            lineColor.setStroke()
            lineColor.setFill()
            key.lineWidth = 1.2
            key.stroke()
            speaker.fill()
            returnMark.fill()
            return true
        }
        // Keep the requested black-and-white palette in either menu-bar theme.
        image.isTemplate = false
        return image
    }

    private static func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
