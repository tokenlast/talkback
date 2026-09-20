import AppKit

/// Hand-drawn vector interpretation of the selected gooseneck microphone (#8).
/// Shared by the menu badge and app icon: no bitmap art, gradients, or shadows.
enum TalkbackMark {
    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    // Modal interior pixel of the supplied macOS microphone badge, in its
    // original Display P3 profile. Treating these bytes as sRGB changes the color.
    static var orange: CGColor {
        CGColor(colorSpace: colorSpace, components: [230 / 255.0, 140 / 255.0, 63 / 255.0, 1])!
    }
    static var black: CGColor {
        CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!
    }
    static var paused: CGColor {
        CGColor(colorSpace: colorSpace, components: [0.78, 0.78, 0.78, 1])!
    }

    static func badge(listening: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawBadge(in: rect, context: context, listening: listening)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawBadge(in rect: CGRect, context: CGContext, listening: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 32, y: rect.height / 20)
        let background = listening ? orange : paused
        context.setFillColor(background)
        context.addPath(CGPath(roundedRect: CGRect(x: 1, y: 1, width: 30, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
        drawMicrophone(in: CGRect(x: 7, y: 1, width: 18, height: 18), context: context, background: background)
    }

    static func drawAppIcon(in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(orange)
        let face = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        context.addPath(CGPath(roundedRect: face, cornerWidth: rect.width * 0.20, cornerHeight: rect.height * 0.20, transform: nil))
        context.fillPath()
        drawMicrophone(in: rect.insetBy(dx: rect.width * 0.13, dy: rect.height * 0.13), context: context, background: orange)
    }

    private static func drawMicrophone(in rect: CGRect, context: CGContext, background: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        // Author the drawing on a 24 × 24, top-left-origin grid.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 24, y: -rect.height / 24)
        context.setStrokeColor(black)
        context.setFillColor(background)
        context.setLineWidth(1.3)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let neck = CGMutablePath()
        neck.move(to: CGPoint(x: 6.1, y: 19.7))
        neck.addCurve(to: CGPoint(x: 4.1, y: 8.2), control1: CGPoint(x: 5.7, y: 15.7), control2: CGPoint(x: 3.5, y: 12.3))
        neck.addCurve(to: CGPoint(x: 11.2, y: 1.7), control1: CGPoint(x: 4.6, y: 3.7), control2: CGPoint(x: 7.7, y: 1.4))
        neck.addCurve(to: CGPoint(x: 18, y: 9.4), control1: CGPoint(x: 15.4, y: 1.9), control2: CGPoint(x: 17.2, y: 5.6))
        neck.addLine(to: CGPoint(x: 15.2, y: 10.2))
        neck.addCurve(to: CGPoint(x: 11, y: 4.4), control1: CGPoint(x: 14.5, y: 7), control2: CGPoint(x: 13.6, y: 4.5))
        neck.addCurve(to: CGPoint(x: 6.7, y: 8.8), control1: CGPoint(x: 8.3, y: 4.2), control2: CGPoint(x: 6.6, y: 6.1))
        neck.addCurve(to: CGPoint(x: 8.7, y: 19.6), control1: CGPoint(x: 6.8, y: 12.2), control2: CGPoint(x: 8.6, y: 15.6))
        neck.closeSubpath()
        context.addPath(neck)
        context.drawPath(using: .fillStroke)

        context.setLineWidth(0.85)
        for (start, end) in [
            (CGPoint(x: 4.6, y: 6.4), CGPoint(x: 6.8, y: 7.2)),
            (CGPoint(x: 6.4, y: 3.7), CGPoint(x: 8, y: 5.5)),
            (CGPoint(x: 9.5, y: 1.9), CGPoint(x: 10, y: 4.4)),
            (CGPoint(x: 12.9, y: 2.2), CGPoint(x: 12, y: 4.7)),
            (CGPoint(x: 15.4, y: 4.5), CGPoint(x: 13.5, y: 6.1)),
            (CGPoint(x: 16.9, y: 7.2), CGPoint(x: 14.7, y: 8)),
            (CGPoint(x: 4.4, y: 10), CGPoint(x: 6.8, y: 10)),
            (CGPoint(x: 5.4, y: 13.5), CGPoint(x: 7.6, y: 13)),
            (CGPoint(x: 6.1, y: 17), CGPoint(x: 8.4, y: 16.5))
        ] {
            context.move(to: start)
            context.addLine(to: end)
        }
        context.strokePath()
        context.setLineWidth(1.3)

        let body = CGMutablePath()
        body.move(to: CGPoint(x: 15.5, y: 9.5))
        body.addCurve(to: CGPoint(x: 19.8, y: 11.2), control1: CGPoint(x: 17.4, y: 8.7), control2: CGPoint(x: 19.2, y: 9.2))
        body.addLine(to: CGPoint(x: 21.3, y: 17))
        body.addCurve(to: CGPoint(x: 18.7, y: 20.8), control1: CGPoint(x: 21.9, y: 19.1), control2: CGPoint(x: 20.7, y: 20.3))
        body.addLine(to: CGPoint(x: 17.5, y: 21.1))
        body.addCurve(to: CGPoint(x: 14.3, y: 18.9), control1: CGPoint(x: 15.6, y: 21.4), control2: CGPoint(x: 14.6, y: 20.5))
        body.addLine(to: CGPoint(x: 13.3, y: 13))
        body.addCurve(to: CGPoint(x: 15.5, y: 9.5), control1: CGPoint(x: 13.1, y: 11.2), control2: CGPoint(x: 13.8, y: 10))
        body.closeSubpath()
        context.addPath(body)
        context.drawPath(using: .fillStroke)

        context.move(to: CGPoint(x: 15.5, y: 15.3))
        context.addQuadCurve(to: CGPoint(x: 19, y: 14.4), control: CGPoint(x: 17.4, y: 15.4))
        context.move(to: CGPoint(x: 16.1, y: 18.1))
        context.addQuadCurve(to: CGPoint(x: 19.7, y: 17.2), control: CGPoint(x: 18, y: 18.2))
        context.strokePath()

        let base = CGPath(roundedRect: CGRect(x: 5.2, y: 19.2, width: 4.7, height: 3.6), cornerWidth: 0.8, cornerHeight: 0.8, transform: nil)
        context.addPath(base)
        context.drawPath(using: .fillStroke)
    }
}
