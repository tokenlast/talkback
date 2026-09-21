// Build with the native source files listed in QA.md.
// Uses a synthetic fixture, never the microphone. See QA.md.
import AVFoundation
import CoreMedia
import Foundation
import Speech

@main struct ContinuousSpeechSmoke {
    @MainActor final class State {
        var transcript = VoiceTranscript()
        var committed = 0.0
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard CommandLine.arguments.count >= 2 else { fatalError("Pass the synthetic AIFF fixture path") }
        let path = CommandLine.arguments[1]
        let operatorTest = CommandLine.arguments.contains("--operator")
        let realtime = CommandLine.arguments.contains("--realtime")
        let pauseBoundary = CommandLine.arguments.contains("--pause-boundary")
        let expected: String?
        if let index = CommandLine.arguments.firstIndex(of: "--expected") {
            guard index + 1 < CommandLine.arguments.count else { fatalError("Pass expected fixture text") }
            expected = CommandLine.arguments[index + 1].lowercased()
        } else { expected = nil }
        let (transcriber, format) = try await DictationController.module(locale: "en-US")
        print("Module ready at \(format.sampleRate) Hz")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.setContext(DictationController.recognitionContext())
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let state = State()
        let results = Task { @MainActor in
            for try await result in transcriber.results {
                if operatorTest || expected != nil {
                    print("Synthetic result \(result.range.start.seconds)...\(result.range.end.seconds) final=\(result.isFinal) watermark=\(result.resultsFinalizationTime.seconds): \(String(result.text.characters))")
                }
                if result.range.end.seconds > state.committed + 0.001 {
                    state.transcript.update(start: result.range.start.seconds, end: result.range.end.seconds,
                                            text: String(result.text.characters), isFinal: result.isFinal)
                }
                state.transcript.finalize(through: result.resultsFinalizationTime.seconds)
            }
        }
        try await analyzer.start(inputSequence: stream)
        let fileFormat = try AVAudioFile(forReading: URL(fileURLWithPath: path)).processingFormat
        let converter = try VoiceAudioConverter(from: fileFormat, to: format)
        var failures = 0
        for iteration in 1...(operatorTest || expected != nil ? 5 : 20) {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: 2048)!
            var boundary = state.committed
            var requestedBoundary: Double?
            while file.framePosition < file.length {
                try file.read(into: buffer)
                let packet = try converter.convert(buffer)
                continuation.yield(AnalyzerInput(buffer: packet.buffer))
                boundary = packet.end
                try await Task.sleep(for: .seconds(realtime ? Double(buffer.frameLength) / fileFormat.sampleRate : 0.01))
                // Fixtures end in two seconds of silence: request finalization
                // after roughly 0.7 seconds, then keep streaming the remaining audio.
                if pauseBoundary && requestedBoundary == nil &&
                    Double(file.length - file.framePosition) / fileFormat.sampleRate <= 1.3 {
                    requestedBoundary = boundary
                    try await analyzer.finalize(through: CMTime(seconds: boundary - 0.001, preferredTimescale: 1_000_000))
                }
            }
            boundary = requestedBoundary ?? boundary
            print("Finalizing utterance \(iteration) at \(boundary)")
            let began = Date()
            if requestedBoundary == nil {
                try await analyzer.finalize(through: CMTime(seconds: boundary - 0.001, preferredTimescale: 1_000_000))
            }
            for _ in 0..<60 {
                if state.transcript.isFinal(through: boundary) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard state.transcript.isFinal(through: boundary) else { throw VoiceError("Final result missing") }
            let text = state.transcript.consume(through: boundary).lowercased()
            let normalized = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            let valid: Bool
            if let expected { valid = normalized == expected }
            else if operatorTest { valid = ["add operator", "add an operator", "add a operator"].contains(normalized) }
            else { valid = text.contains("mute this track") && text.contains("solo this track") && !text.contains("unmute") }
            if !valid || !state.transcript.text.isEmpty {
                failures += 1
                print("FAIL synthetic fixture transcription: \(text)")
            } else {
                if pauseBoundary {
                    print("PASS utterance \(iteration): final-only result at requested pause boundary")
                } else {
                    print("PASS utterance \(iteration): final result in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
                }
            }
            state.committed = boundary
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await results.value
        if failures > 0 {
            print("\(failures) fixture phrases failed")
            exit(1)
        }
    }
}
