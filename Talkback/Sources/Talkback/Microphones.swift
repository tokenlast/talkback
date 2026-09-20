import AudioToolbox
import CoreAudio
import Foundation

struct Microphone: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let builtIn: Bool
}

enum Microphones {
    static func selected(in devices: [Microphone], uid: String?) -> Microphone? {
        if let uid, !uid.isEmpty { return devices.first { $0.uid == uid } }
        return devices.first { $0.builtIn }
    }

    static var inputs: [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty, AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id -> Microphone? in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            // AVAudioEngine's private, short-lived aggregate is not a selectable
            // microphone. User-created aggregate and virtual inputs remain listed.
            guard !name.hasPrefix("CADefaultDeviceAggregate-") else { return nil }
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            return Microphone(id: id, uid: uid, name: name, builtIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }.sorted { left, right in
            if left.builtIn != right.builtIn { return left.builtIn }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func currentDevice(_ unit: AudioUnit) -> AudioDeviceID? {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size) == noErr else { return nil }
        return device
    }
}

/// Read-only audio-unit binding shared with the input callback. The engine owns
/// this unit and removes its tap before stopping or releasing the engine.
struct MicrophoneBinding: @unchecked Sendable {
    let unit: AudioUnit
    let id: AudioDeviceID
    var isCurrent: Bool { Microphones.currentDevice(unit) == id }
}
