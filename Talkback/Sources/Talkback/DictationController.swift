import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import Speech

/// On-device streaming recognition. No audio is written to disk or sent to the cloud.
@MainActor
final class DictationController {
    var onTranscript: ((String) -> Void)?
    var onSilence: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var finishTask: Task<Void, Never>?
    private var generation = UUID()
    private var transcript = VoiceTranscript()
    private var endpoint = VoiceEndpoint()
    private var audioTime = 0.0
    private var lastAudioAt = 0.0
    private var committedThrough = 0.0
    private var finishBoundary: Double?
    private var finishRequestedAt = 0.0
    private(set) var isPreparing = false
    private(set) var isFinishing = false
    private(set) var isListening = false {
        didSet { if isListening != oldValue { onListeningChange?(isListening) } }
    }

    func start(language: InterfaceLanguage) {
        guard !isListening, !isPreparing else { return }
        stop()
        let id = generation
        isPreparing = true
        onStatus?("Preparing speech…")
        let locale = language == .ja ? "ja-JP" : "en-US"
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                guard await Self.microphoneIsAuthorized() else {
                    throw VoiceError("Allow Talkback in System Settings → Privacy & Security → Microphone.")
                }
                guard self.generation == id else { return }
                let (transcriber, format) = try await Self.module(locale: locale)
                guard self.generation == id else { return }
                let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
                self.analyzer = analyzer
                try await analyzer.prepareToAnalyze(in: format)
                guard self.generation == id else { await analyzer.cancelAndFinishNow(); return }
                try self.begin(transcriber: transcriber, format: format, analyzer: analyzer, id: id)
            } catch {
                guard self.generation == id else { return }
                self.fail(error.localizedDescription)
            }
        })
    }

    func stop() {
        generation = UUID()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        finishTask?.cancel()
        finishTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
            Log.shared.write("voice microphone stopped")
        }
        continuation?.finish()
        continuation = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        transcript = VoiceTranscript()
        endpoint = VoiceEndpoint()
        audioTime = 0
        committedThrough = 0
        finishBoundary = nil
        isFinishing = false
        isPreparing = false
        isListening = false
    }

    /// Flush one utterance while keeping the microphone and model running.
    func finish() {
        guard isListening, !isFinishing, let analyzer, transcript.hasSpeech else { return }
        let id = generation
        isFinishing = true
        finishBoundary = audioTime
        finishRequestedAt = ProcessInfo.processInfo.systemUptime
        let boundary = audioTime
        finishTask = Task { [weak self] in
            do {
                // The endpoint is inclusive: stay inside the last audio buffer.
                try await analyzer.finalize(through: CMTime(seconds: max(0, boundary - 0.001), preferredTimescale: 1_000_000))
                guard let self, self.generation == id else { return }
                self.commitIfReady()
            } catch {
                guard let self, self.generation == id else { return }
                self.fail("Could not finish speech.")
            }
        }
    }

    private func begin(transcriber: SpeechTranscriber, format: AVAudioFormat, analyzer: SpeechAnalyzer, id: UUID) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let chosenUID = UserDefaults.standard.string(forKey: "TalkbackMicrophoneUID")
        guard let microphone = Microphones.selected(in: Microphones.inputs, uid: chosenUID) else {
            throw VoiceError(chosenUID?.isEmpty == false ? "Selected microphone unavailable. Choose an input in Settings." : "No built-in microphone. Choose an input in Settings.")
        }
        guard let unit = input.audioUnit else { throw VoiceError("Microphone audio unit unavailable.") }
        var device = microphone.id
        let deviceStatus = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout.size(ofValue: device)))
        guard deviceStatus == noErr, Microphones.currentDevice(unit) == microphone.id else {
            throw VoiceError("Could not open the selected microphone (\(deviceStatus)).")
        }
        let microphoneBinding = MicrophoneBinding(unit: unit, id: microphone.id)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceError("No microphone input is available.")
        }
        let conversion = try VoiceAudioConverter(from: inputFormat, to: format)
        let noiseDB = TalkbackSettings.noiseFloor
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(256))
        self.continuation = continuation
        tasks.append(Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == id else { return }
                    let end = result.range.end.seconds
                    if end > self.committedThrough + 0.001 {
                        self.transcript.update(start: result.range.start.seconds, end: end,
                                               text: String(result.text.characters), isFinal: result.isFinal)
                        self.endpoint.textChanged(at: ProcessInfo.processInfo.systemUptime)
                        self.onTranscript?(self.transcript.text)
                    }
                    self.transcript.finalizedThrough = max(self.transcript.finalizedThrough, result.resultsFinalizationTime.seconds)
                    self.commitIfReady()
                }
            } catch {
                guard let self, self.generation == id else { return }
                self.fail("Speech recognition stopped.")
            }
        })
        tasks.append(Task { [weak self] in
            do { try await analyzer.start(inputSequence: stream) }
            catch {
                guard let self, self.generation == id else { return }
                self.fail("Speech input stopped.")
            }
        })
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { @Sendable [weak self] buffer, _ in
            do {
                let packet = try conversion.convert(buffer)
                guard packet.buffer.frameLength > 0 else { return }
                guard microphoneBinding.isCurrent else {
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id else { return }
                        self.fail("Selected microphone disconnected.")
                    }
                    return
                }
                let audible = VoiceAudioConverter.isAudible(buffer, thresholdDB: noiseDB)
                let now = ProcessInfo.processInfo.systemUptime
                // Let SpeechAnalyzer append exact frame durations. Rounding
                // timestamps to a different sample rate causes tiny overlaps.
                let delivery = continuation.yield(AnalyzerInput(buffer: packet.buffer))
                Task { @MainActor [weak self] in
                    guard let self, self.generation == id else { return }
                    if case .dropped = delivery { self.fail("Speech input could not keep up."); return }
                    self.audioTime = packet.end
                    self.lastAudioAt = now
                    self.endpoint.audioArrived(at: now, audible: audible)
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == id else { return }
                    self.fail("Microphone changed.")
                }
            }
        }
        self.engine = engine
        engine.prepare()
        try engine.start()
        isPreparing = false
        isListening = true
        lastAudioAt = ProcessInfo.processInfo.systemUptime
        onStatus?("Listening")
        Log.shared.write("voice microphone started; on-device SpeechAnalyzer")
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, self.generation == id else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastAudioAt > 3 { self.fail("Microphone input interrupted."); return }
                if self.isFinishing {
                    self.commitIfReady()
                    if self.isFinishing && now - self.finishRequestedAt > 3 { self.fail("Speech finalization timed out."); return }
                } else if TalkbackSettings.autoSubmit && self.endpoint.shouldFinish(at: now, hasText: self.transcript.hasSpeech, pause: TalkbackSettings.pause) {
                    self.finish()
                }
            }
        })
    }

    private func commitIfReady() {
        guard let boundary = finishBoundary, transcript.isFinal(through: boundary) else { return }
        let text = transcript.consume(through: boundary)
        committedThrough = boundary
        finishBoundary = nil
        isFinishing = false
        endpoint = VoiceEndpoint()
        onSilence?(text)
    }

    private func fail(_ message: String) {
        stop()
        onError?(message)
    }

    static func module(locale: String) async throws -> (SpeechTranscriber, AVAudioFormat) {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw VoiceError("On-device speech is unavailable for this language.")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        try await AssetInventory.reserve(locale: locale)
        if await AssetInventory.status(forModules: [transcriber]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError("No compatible speech audio format.")
        }
        return (transcriber, format)
    }

    private nonisolated static func microphoneIsAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

struct VoiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Only called serially by the engine input tap; each output owns its sample memory.
final class VoiceAudioConverter: @unchecked Sendable {
    struct Packet: @unchecked Sendable { let buffer: AVAudioPCMBuffer; let start: Double; let end: Double }
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var frames: Int64 = 0
    // AVAudioConverter invokes this synchronously on this tap's serial thread.
    private final class Supply: @unchecked Sendable {
        let input: AVAudioPCMBuffer
        var supplied = false
        init(_ input: AVAudioPCMBuffer) { self.input = input }
    }

    init(from: AVAudioFormat, to: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw VoiceError("Unsupported microphone format.") }
        self.converter = converter
        outputFormat = to
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> Packet {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { throw VoiceError("Audio allocation failed.") }
        let supply = Supply(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supply.supplied { state.pointee = .noDataNow; return nil }
            supply.supplied = true; state.pointee = .haveData
            return supply.input
        }
        if let error { throw error }
        guard status != .error else { throw VoiceError("Audio conversion failed.") }
        let start = Double(frames) / outputFormat.sampleRate
        frames += Int64(output.frameLength)
        return Packet(buffer: output, start: start, end: Double(frames) / outputFormat.sampleRate)
    }

    static func isAudible(_ buffer: AVAudioPCMBuffer, thresholdDB: Double = -48) -> Bool {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        var energy: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 8) { energy += channels[channel][i] * channels[channel][i] }
        }
        let count = Float((Int(buffer.frameLength) + 7) / 8 * Int(buffer.format.channelCount))
        return energy / count > Float(pow(10, thresholdDB / 10))
    }
}
