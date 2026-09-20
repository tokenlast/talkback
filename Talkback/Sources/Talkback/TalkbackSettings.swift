import Foundation

enum TalkbackSettings {
    static let changed = Notification.Name("TalkbackSettingsChanged")
    static let pauseRange = 0.1...10.0
    static func boundedPause(_ value: Double) -> Double {
        min(pauseRange.upperBound, max(pauseRange.lowerBound, value.isFinite ? value : 0.7))
    }
    static var pause: Double {
        boundedPause(UserDefaults.standard.object(forKey: "TalkbackPause") as? Double ?? 0.7)
    }
    static var noiseFloor: Double {
        let value = UserDefaults.standard.object(forKey: "TalkbackNoiseFloor") as? Double ?? -48
        return min(-15, max(-70, value.isFinite ? value : -48))
    }
    static var autoSubmit: Bool { UserDefaults.standard.object(forKey: "TalkbackAutoSubmit") as? Bool ?? true }
    static var liveOnly: Bool { UserDefaults.standard.object(forKey: "TalkbackLiveOnly") as? Bool ?? true }
    static var commandsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talkback/commands.txt")
    }
    static let commandExample = """
    # One exact phrase => supported command per line.
    # Remove # to enable an example. Matching ignores case and final punctuation.
    # bring it forward => turn this track up 3 dB
    # quiet please => mute this track
    # my synth => throw Serum on a new track in Instruments
    # ready to go => arm this track and start recording
    """
}
