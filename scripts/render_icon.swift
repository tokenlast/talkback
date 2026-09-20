// Compile with TalkbackMark.swift; renders the same supplied artwork as the app.
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderIcon {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { fatalError("Pass source logo PNG, output PNG, [badge|badge-small|paused]") }
        guard let logo = TalkbackMark.loadLogoMask(from: URL(fileURLWithPath: CommandLine.arguments[1])) else { fatalError("Could not read source logo") }
        let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "app"
        let width = mode == "app" ? 1024 : mode == "badge-small" ? 64 : 320
        let height = mode == "app" ? 1024 : mode == "badge-small" ? 40 : 200
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: TalkbackMark.colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if mode == "app" { TalkbackMark.drawAppIcon(in: rect, context: context, logo: logo) }
        else { TalkbackMark.drawBadge(in: rect, context: context, listening: mode != "paused", logo: logo) }
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
    }
}
