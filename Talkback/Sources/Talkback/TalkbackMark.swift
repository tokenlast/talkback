import AppKit
import ImageIO

/// Black-only menu artwork; the app icon retains its solid white keyline.
enum TalkbackMark {
    struct Logo {
        let ink: CGImage
        let outline: CGImage
        let outlineScale: CGFloat
    }
    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    // Modal interior pixel of the supplied macOS microphone badge, in its
    // original Display P3 profile. Treating these bytes as sRGB changes the color.
    static var orange: CGColor {
        CGColor(colorSpace: colorSpace, components: [230 / 255.0, 140 / 255.0, 63 / 255.0, 1])!
    }
    static var black: CGColor {
        CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!
    }
    static var white: CGColor {
        CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!
    }
    static var paused: CGColor {
        CGColor(colorSpace: colorSpace, components: [0.78, 0.78, 0.78, 1])!
    }

    private static let bundledLogo: Logo? = {
        guard let url = Bundle.main.url(forResource: "TalkbackLogo", withExtension: "png") else { return nil }
        return loadLogoMask(from: url)
    }()

    static func loadLogoMask(from url: URL) -> Logo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let ink = mask(from: image), let silhouette = silhouette(from: ink) else { return nil }
        let radius = CGFloat(image.width) * 0.045
        let padding = Int(ceil(radius)) + 2
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let original = CGRect(x: padding, y: padding, width: image.width, height: image.height)
        context.draw(silhouette, in: original)
        // Union evenly spaced copies of the filled silhouette. This creates a
        // centered, hard white keyline with no blur, shadow, or clipped edges.
        context.setBlendMode(.darken)
        for step in 0..<48 {
            let angle = CGFloat(step) * 2 * .pi / 48
            context.draw(silhouette, in: original.offsetBy(dx: cos(angle) * radius, dy: sin(angle) * radius))
        }
        guard let padded = context.makeImage() else { return nil }
        guard let outline = mask(from: padded) else { return nil }
        return Logo(ink: ink, outline: outline, outlineScale: CGFloat(width) / CGFloat(image.width))
    }

    /// Keep the paper inside the closed line drawing white, as in the supplied
    /// logo. Only the exterior paper is transparent; no tiny orange holes remain.
    private static func silhouette(from mask: CGImage) -> CGImage? {
        guard let data = mask.dataProvider?.data else { return nil }
        let source = [UInt8](data as Data)
        let width = mask.width, height = mask.height
        var exterior = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        func visit(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = y * width + x
            guard !exterior[index], source[y * mask.bytesPerRow + x] >= 128 else { return }
            exterior[index] = true
            queue.append(index)
        }
        for x in 0..<width { visit(x, 0); visit(x, height - 1) }
        for y in 0..<height { visit(0, y); visit(width - 1, y) }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor], x = index % width, y = index / width
            cursor += 1
            visit(x - 1, y); visit(x + 1, y); visit(x, y - 1); visit(x, y + 1)
        }
        let pixels = (0..<(width * height)).map { exterior[$0] ? source[($0 / width) * mask.bytesPerRow + $0 % width] : UInt8(0) }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func mask(from image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        guard let provider = context.makeImage()?.dataProvider else { return nil }
        // Quartz image masks use 0 for ink and 255 for transparent paper.
        return CGImage(maskWidth: image.width, height: image.height, bitsPerComponent: 8,
                       bitsPerPixel: 8, bytesPerRow: image.width, provider: provider,
                       decode: nil, shouldInterpolate: true)
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

    static func drawBadge(in rect: CGRect, context: CGContext, listening: Bool, logo: Logo? = nil) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 32, y: rect.height / 20)
        let background = listening ? orange : paused
        context.setFillColor(background)
        context.addPath(CGPath(roundedRect: CGRect(x: 1, y: 1, width: 30, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
        drawMicrophone(in: CGRect(x: 8, y: 2, width: 16, height: 16), context: context, logo: logo, whiteBorder: false)
    }

    static func drawAppIcon(in rect: CGRect, context: CGContext, logo: Logo? = nil) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(orange)
        let face = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        context.addPath(CGPath(roundedRect: face, cornerWidth: rect.width * 0.20, cornerHeight: rect.height * 0.20, transform: nil))
        context.fillPath()
        drawMicrophone(in: rect.insetBy(dx: rect.width * 0.13, dy: rect.height * 0.13), context: context, logo: logo, whiteBorder: true)
    }

    private static func drawMicrophone(in rect: CGRect, context: CGContext, logo: Logo?, whiteBorder: Bool) {
        guard let logo = logo ?? bundledLogo else { return }
        if whiteBorder {
            let margin = rect.width * (logo.outlineScale - 1) / 2
            paint(logo.outline, in: rect.insetBy(dx: -margin, dy: -margin), color: white, context: context)
        }
        paint(logo.ink, in: rect, color: black, context: context)
    }

    private static func paint(_ mask: CGImage, in rect: CGRect, color: CGColor, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high
        context.clip(to: rect, mask: mask)
        context.setFillColor(color)
        context.fill(rect)
    }
}
