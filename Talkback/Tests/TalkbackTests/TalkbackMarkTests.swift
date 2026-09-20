import AppKit
import XCTest
@testable import Talkback

final class TalkbackMarkTests: XCTestCase {
    func testExactScreenshotColorAndOpaqueBlack() {
        XCTAssertEqual(TalkbackMark.orange.colorSpace?.name, CGColorSpace.displayP3)
        XCTAssertEqual(TalkbackMark.orange.components!, [230 / 255.0, 140 / 255.0, 63 / 255.0, 1])
        XCTAssertEqual(TalkbackMark.black.components!, [0, 0, 0, 1])
    }

    func testBadgeHasNoExtraColorsOrShadows() {
        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8,
                                bytesPerRow: 1280, space: TalkbackMark.colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Disable only edge antialiasing to test the authored paint palette.
        context.setShouldAntialias(false)
        TalkbackMark.drawBadge(in: CGRect(x: 0, y: 0, width: 320, height: 200), context: context, listening: true)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var hasBlack = false
        var hasOrange = false
        for offset in stride(from: 0, to: 320 * 200 * 4, by: 4) {
            let pixel = Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
            if pixel == [0, 0, 0, 0] { continue }
            if pixel == [0, 0, 0, 255] { hasBlack = true; continue }
            if pixel == [230, 140, 63, 255] { hasOrange = true; continue }
            XCTFail("Unexpected paint: \(pixel)")
            return
        }
        XCTAssertTrue(hasBlack)
        XCTAssertTrue(hasOrange)
    }

    @MainActor func testMenuWidthDoesNotChangeWhenPaused() {
        XCTAssertEqual(TalkbackMark.badge(listening: true).size, NSSize(width: 32, height: 20))
        XCTAssertEqual(TalkbackMark.badge(listening: false).size, NSSize(width: 32, height: 20))
        XCTAssertFalse(TalkbackMark.badge(listening: true).isTemplate)
    }
}
