// Compile with TalkbackMark.swift; renders the exact native paths, not AI artwork.
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct RenderIcon {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Pass output PNG [badge|badge-small|paused]") }
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "app"
        let width = mode == "app" ? 1024 : mode == "badge-small" ? 64 : 320
        let height = mode == "app" ? 1024 : mode == "badge-small" ? 40 : 200
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: TalkbackMark.colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if mode == "app" { TalkbackMark.drawAppIcon(in: rect, context: context) }
        else { TalkbackMark.drawBadge(in: rect, context: context, listening: mode != "paused") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
    }
}
