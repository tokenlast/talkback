import AVFoundation
import Foundation
import Speech

@MainActor
final class DictationController: NSObject, @unchecked Sendable {
    var onTranscript: ((String) -> Void)?
    var onSilence: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var generation = 0
    private var transcript = ""
    private var hasInputTap = false

    private static let silenceDelay: Duration = .seconds(1)

    private(set) var isListening = false {
        didSet {
            if isListening != oldValue { onListeningChange?(isListening) }
        }
    }
    private(set) var isPreparing = false

    func start(language: InterfaceLanguage) {
        stop()
        generation += 1
        let requestedGeneration = generation
        let locale = Locale(identifier: language == .ja ? "ja-JP" : "en-US")
        isPreparing = true

        Task { [weak self] in
            guard let self else { return }
            guard await Self.microphoneIsAuthorized() else {
                guard self.generation == requestedGeneration else { return }
                self.isPreparing = false
                self.onError?("Microphone access is required for dictation.")
                return
            }
            guard await Self.speechIsAuthorized() else {
                guard self.generation == requestedGeneration else { return }
                self.isPreparing = false
                self.onError?("Speech Recognition access is required for dictation.")
                return
            }
            guard self.generation == requestedGeneration else { return }
            self.isPreparing = false
            self.beginRecognition(locale: locale, generation: requestedGeneration)
        }
    }

    func stop() {
        generation += 1
        silenceTask?.cancel()
        silenceTask = nil
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""
        isPreparing = false
        isListening = false
    }

    private func beginRecognition(locale: Locale, generation: Int) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            onError?("Speech Recognition is unavailable right now.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            onError?("On-device Speech Recognition is unavailable for this language.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request
        transcript = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                if let text, !text.isEmpty { self.receive(text: text, isFinal: isFinal) }
                if let errorMessage, self.transcript.isEmpty {
                    self.onError?(errorMessage)
                    self.stop()
                }
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("No microphone input is available.")
            stop()
            return
        }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInputTap = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            onError?(error.localizedDescription)
            stop()
        }
    }

    private func receive(text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let changed = trimmed != transcript
        transcript = trimmed
        if changed { onTranscript?(trimmed) }
        scheduleSilenceSubmission()
        if isFinal { submitAfterSilence(generation: generation, transcript: trimmed) }
    }

    private func scheduleSilenceSubmission() {
        let expectedGeneration = generation
        let expectedTranscript = transcript
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.silenceDelay) }
            catch { return }
            self?.submitAfterSilence(generation: expectedGeneration, transcript: expectedTranscript)
        }
    }

    private func submitAfterSilence(generation expectedGeneration: Int, transcript expectedTranscript: String) {
        guard generation == expectedGeneration, transcript == expectedTranscript, !transcript.isEmpty else { return }
        let submitted = transcript
        stop()
        onSilence?(submitted)
    }

    private nonisolated static func microphoneIsAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private nonisolated static func speechIsAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
