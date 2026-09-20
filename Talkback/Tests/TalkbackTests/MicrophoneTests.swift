import XCTest
@testable import Talkback

final class MicrophoneTests: XCTestCase {
    private let builtIn = Microphone(id: 1, uid: "built-in", name: "Mac microphone", builtIn: true)
    private let interface = Microphone(id: 2, uid: "interface", name: "Audio interface", builtIn: false)

    func testDefaultSelectsBuiltInEvenWhenInterfaceComesFirst() {
        XCTAssertEqual(Microphones.selected(in: [interface, builtIn], uid: nil), builtIn)
        XCTAssertEqual(Microphones.selected(in: [interface, builtIn], uid: ""), builtIn)
    }

    func testExplicitInputUsesStableUIDInsteadOfTransientDeviceID() {
        let reconnected = Microphone(id: 99, uid: interface.uid, name: interface.name, builtIn: false)
        XCTAssertEqual(Microphones.selected(in: [builtIn, reconnected], uid: interface.uid), reconnected)
    }

    func testUnavailableInputNeverFallsBackToAnotherMic() {
        XCTAssertNil(Microphones.selected(in: [interface], uid: nil))
        XCTAssertNil(Microphones.selected(in: [builtIn], uid: interface.uid))
        XCTAssertNil(Microphones.selected(in: [], uid: nil))
    }
}
