import AppKit

/// A template mask drawn at menu-bar size: keyboard → iPhone.
/// The status item supplies the inactive opacity and the system supplies its tint.
enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 20), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let keyboard = roundedRect(NSRect(x: 0.95, y: 4.2, width: 10.8, height: 11.6), radius: 1.65)
            let keys: [NSBezierPath] = (0..<2).flatMap { row -> [NSBezierPath] in
                (0..<3).map { column in
                    roundedRect(NSRect(x: 2.6 + CGFloat(column) * 2.8,
                                       y: 6.55 + CGFloat(row) * 4.0,
                                       width: 1.9, height: 2.9), radius: 0.45)
                }
            }
            let phone = roundedRect(NSRect(x: 20.0, y: 1.25, width: 7.05, height: 17.5), radius: 1.85)
            let speaker = roundedRect(NSRect(x: 22.25, y: 15.75, width: 2.55, height: 1.0), radius: 0.5)
            let homeBar = roundedRect(NSRect(x: 22.25, y: 3.25, width: 2.55, height: 1.0), radius: 0.5)

            if active {
                // Even-odd holes stay transparent rather than painting a background
                // color, so template tinting also works in dark menu bars.
                keyboard.windingRule = .evenOdd
                keys.forEach { keyboard.append($0) }
                keyboard.fill()
                phone.windingRule = .evenOdd
                phone.append(speaker)
                phone.append(homeBar)
                phone.fill()
            } else {
                keyboard.lineWidth = 1.7
                keyboard.stroke()
                keys.forEach { $0.fill() }
                phone.lineWidth = 1.7
                phone.stroke()
                speaker.fill()
                homeBar.fill()
            }

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.8
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 13.25, y: 10.0))
            arrow.line(to: NSPoint(x: 17.8, y: 10.0))
            arrow.move(to: NSPoint(x: 15.6, y: 12.35))
            arrow.line(to: NSPoint(x: 17.95, y: 10.0))
            arrow.line(to: NSPoint(x: 15.6, y: 7.65))
            arrow.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
