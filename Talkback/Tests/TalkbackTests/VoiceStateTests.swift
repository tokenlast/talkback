import XCTest
@testable import Talkback

final class VoiceStateTests: XCTestCase {
    func testConfigurablePauseStillRequiresStableWords() {
        var state = VoiceEndpoint()
        state.textChanged(at: 1)
        state.audioArrived(at: 1, audible: true)
        state.audioArrived(at: 1.4, audible: false)
        XCTAssertTrue(state.shouldFinish(at: 1.4, hasText: true, pause: 0.3))
        XCTAssertFalse(state.shouldFinish(at: 1.4, hasText: true, pause: 1))
        state.textChanged(at: 1.35)
        XCTAssertFalse(state.shouldFinish(at: 1.4, hasText: true, pause: 0.3))
    }

    func testLongConversationIsDiscardedRatherThanTruncatedIntoACommand() {
        var transcript = VoiceTranscript()
        transcript.update(start: 0, end: 40, text: String(repeating: "talk ", count: 110), isFinal: false)
        XCTAssertTrue(transcript.overflowed)
        transcript.update(start: 0, end: 40, text: "mute this track", isFinal: true)
        XCTAssertEqual(transcript.consume(through: 41), "")
        XCTAssertFalse(transcript.overflowed)
        transcript.update(start: 42, end: 44, text: "solo this track", isFinal: true)
        XCTAssertEqual(transcript.consume(through: 45), "solo this track")
    }

    func testSilenceRequiresAudioNotJustStableWords() {
        var state = VoiceEndpoint()
        state.textChanged(at: 1)
        state.audioArrived(at: 1, audible: true)
        state.audioArrived(at: 1.9, audible: false)
        XCTAssertFalse(state.shouldFinish(at: 1.9, hasText: true))
        state.audioArrived(at: 2.1, audible: false)
        XCTAssertTrue(state.shouldFinish(at: 2.1, hasText: true))
        XCTAssertFalse(state.shouldFinish(at: 3, hasText: true), "A dead mic is not silence")
        XCTAssertFalse(state.shouldFinish(at: 2.1, hasText: false))
    }

    func testSoundResetsEndpoint() {
        var state = VoiceEndpoint()
        state.textChanged(at: 1)
        state.audioArrived(at: 2, audible: true)
        XCTAssertFalse(state.shouldFinish(at: 2.1, hasText: true))
    }

    func testPartialMustBeReplacedAndFinalBeforeSubmission() {
        var transcript = VoiceTranscript()
        transcript.update(start: 0, end: 1, text: "unmute", isFinal: false)
        XCTAssertFalse(transcript.isFinal(through: 2))
        transcript.update(start: 0, end: 1.5, text: "mute this track", isFinal: true)
        XCTAssertTrue(transcript.isFinal(through: 2))
        XCTAssertEqual(transcript.consume(through: 2), "mute this track")
        XCTAssertEqual(transcript.consume(through: 2), "")
    }

    func testFutureSpeechSurvivesPreviousCommit() {
        var transcript = VoiceTranscript()
        transcript.update(start: 0, end: 1, text: "mute this track", isFinal: true)
        transcript.update(start: 3, end: 4, text: "solo this track", isFinal: false)
        XCTAssertTrue(transcript.isFinal(through: 2))
        XCTAssertEqual(transcript.consume(through: 2), "mute this track")
        XCTAssertEqual(transcript.text, "solo this track")
    }
}
