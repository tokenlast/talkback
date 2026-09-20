import AVFoundation
import XCTest
@testable import Talkback

final class VoiceAudioTests: XCTestCase {
    func testMeterAndThresholdUseTheSameSignal() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        for index in 0..<1024 { buffer.floatChannelData![0][index] = 0 }
        XCTAssertEqual(VoiceAudioConverter.levelDB(buffer), -160)
        XCTAssertFalse(VoiceAudioConverter.isAudible(buffer))
        for index in 0..<1024 { buffer.floatChannelData![0][index] = 0.01 }
        XCTAssertEqual(VoiceAudioConverter.levelDB(buffer), -40, accuracy: 0.001)
        XCTAssertTrue(VoiceAudioConverter.isAudible(buffer, thresholdDB: -48))
        XCTAssertFalse(VoiceAudioConverter.isAudible(buffer, thresholdDB: -30))
    }
}
