import AppKit
import XCTest
@testable import Talkback

final class TalkbackMarkTests: XCTestCase {
    private var logoURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/TalkbackLogo.png")
    }

    func testSuppliedLogoLoadsAsAnUncoloredMask() throws {
        let logo = try XCTUnwrap(TalkbackMark.loadLogoMask(from: logoURL))
        XCTAssertTrue(logo.ink.isMask)
        XCTAssertEqual(logo.ink.width, 360)
        XCTAssertEqual(logo.ink.height, 360)
        XCTAssertEqual(logo.ink.bitsPerPixel, 8)
        XCTAssertTrue(logo.outline.isMask)
        XCTAssertGreaterThan(logo.outline.width, logo.ink.width)
        XCTAssertGreaterThan(logo.outlineScale, 1)
        XCTAssertEqual(CGFloat(logo.outline.width), CGFloat(logo.ink.width) * logo.outlineScale, accuracy: 0.01)
        XCTAssertEqual(logo.outline.height, logo.outline.width)
        let pixels = [UInt8](try XCTUnwrap(logo.outline.dataProvider?.data) as Data)
        func hasInk(row: Int) -> Bool {
            let start = row * logo.outline.bytesPerRow
            return pixels[start..<(start + logo.outline.width)].contains { $0 < 128 }
        }
        XCTAssertFalse(hasInk(row: 0), "Keep transparent breathing room outside the outline")
        XCTAssertTrue(hasInk(row: 6), "The thick top border must not be cropped")
        XCTAssertTrue(hasInk(row: logo.outline.height - 7), "The thick bottom border must not be cropped")
    }

    func testExactScreenshotColorAndOpaqueBlack() {
        XCTAssertEqual(TalkbackMark.orange.colorSpace?.name, CGColorSpace.displayP3)
        XCTAssertEqual(TalkbackMark.orange.components!, [230 / 255.0, 140 / 255.0, 63 / 255.0, 1])
        XCTAssertEqual(TalkbackMark.black.components!, [0, 0, 0, 1])
        XCTAssertEqual(TalkbackMark.white.components!, [1, 1, 1, 1])
    }

    func testMenuLogoHasOnlyBlackInkInBothStates() throws {
        let logo = try XCTUnwrap(TalkbackMark.loadLogoMask(from: logoURL))
        for listening in [true, false] {
            let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8,
                                    bytesPerRow: 1280, space: TalkbackMark.colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setShouldAntialias(false)
            TalkbackMark.drawBadge(in: CGRect(x: 0, y: 0, width: 320, height: 200), context: context, listening: listening, logo: logo)
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            let background: [Double] = listening ? [230, 140, 63] : [199, 199, 199]
            var hasBlack = false
            for offset in stride(from: 0, to: 320 * 200 * 4, by: 4) {
                if bytes[offset + 3] == 0 { continue }
                let rgb = (0..<3).map { Double(bytes[offset + $0]) }
                if rgb == [0, 0, 0] { hasBlack = true }
                let coverage = rgb[0] / background[0]
                XCTAssertLessThanOrEqual(coverage, 1, "No white fill or border in the menu logo")
                XCTAssertEqual(rgb[1], background[1] * coverage, accuracy: 1.5)
                XCTAssertEqual(rgb[2], background[2] * coverage, accuracy: 1.5)
            }
            XCTAssertTrue(hasBlack)
        }
    }

    func testAppIconKeepsBlackInkWhiteKeylineAndOrangeBackground() throws {
        let logo = try XCTUnwrap(TalkbackMark.loadLogoMask(from: logoURL))
        let context = CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8,
                                bytesPerRow: 1280, space: TalkbackMark.colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Disable only edge antialiasing to test the authored paint palette.
        context.setShouldAntialias(false)
        TalkbackMark.drawAppIcon(in: CGRect(x: 0, y: 0, width: 320, height: 320), context: context, logo: logo)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var hasBlack = false
        var hasOrange = false
        var whitePixels = 0
        for offset in stride(from: 0, to: 320 * 320 * 4, by: 4) {
            let pixel = Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
            if pixel == [0, 0, 0, 0] { continue }
            if pixel == [0, 0, 0, 255] { hasBlack = true; continue }
            if pixel == [230, 140, 63, 255] { hasOrange = true; continue }
            if pixel == [255, 255, 255, 255] { whitePixels += 1; continue }
            // Source and keyline edges blend between the three authored paints.
            XCTAssertEqual(pixel[3], 255)
            XCTAssertGreaterThanOrEqual(pixel[0], pixel[1])
            XCTAssertGreaterThanOrEqual(pixel[1], pixel[2])
        }
        XCTAssertTrue(hasBlack)
        XCTAssertTrue(hasOrange)
        XCTAssertGreaterThan(whitePixels, 1000, "The white keyline must be substantial, not a faint edge")
    }

    @MainActor func testMenuWidthDoesNotChangeWhenPaused() {
        XCTAssertEqual(TalkbackMark.badge(listening: true).size, NSSize(width: 32, height: 20))
        XCTAssertEqual(TalkbackMark.badge(listening: false).size, NSSize(width: 32, height: 20))
        XCTAssertFalse(TalkbackMark.badge(listening: true).isTemplate)
    }
}
