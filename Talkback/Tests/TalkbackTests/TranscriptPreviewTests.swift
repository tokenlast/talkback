import XCTest
@testable import Talkback

final class TranscriptPreviewTests: XCTestCase {
    func testLivePreviewIsReplacedAndFinalIsRetained() {
        var preview = VoiceTranscriptPreview()
        preview.update("add opera")
        preview.update("add Operator")
        XCTAssertEqual(preview.current, "add Operator")
        preview.finish("Add Operator", outcome: "Sent for command processing")
        XCTAssertEqual(preview.current, "")
        XCTAssertTrue(preview.display.contains("Add Operator"))
        preview.update("mute")
        XCTAssertTrue(preview.display.contains("Hearing…\nmute"))
        XCTAssertEqual(preview.last, "Add Operator")
        preview.finish("", outcome: "Empty")
        XCTAssertEqual(preview.last, "Add Operator")
    }

    func testRejectedPhraseIsStillVisibleAndClearErasesEverything() {
        var preview = VoiceTranscriptPreview()
        preview.finish("hello", outcome: "Not sent")
        XCTAssertTrue(preview.display.contains("Not sent\nhello"))
        preview.clear()
        XCTAssertEqual(preview.display, "Waiting for speech…")
        XCTAssertEqual(preview.last, "")
        XCTAssertEqual(preview.outcome, "")
    }

    func testTextStorageIsBounded() {
        var preview = VoiceTranscriptPreview()
        preview.update(String(repeating: "a", count: 2000))
        XCTAssertEqual(preview.current.count, 500)
        preview.finish(String(repeating: "b", count: 2000), outcome: "Not sent")
        XCTAssertEqual(preview.last.count, 500)
    }
}
