import Foundation

enum TalkbackSettings {
    static let changed = Notification.Name("TalkbackSettingsChanged")
    static var pause: Double {
        let value = UserDefaults.standard.object(forKey: "TalkbackPause") as? Double ?? 1
        return min(3, max(0.3, value.isFinite ? value : 1))
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
