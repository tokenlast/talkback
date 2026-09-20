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
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the synthetic AIFF fixture path") }
        let path = CommandLine.arguments[1]
        let (transcriber, format) = try await DictationController.module(locale: "en-US")
        print("Module ready at \(format.sampleRate) Hz")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let state = State()
        let results = Task { @MainActor in
            for try await result in transcriber.results {
                if result.range.end.seconds > state.committed + 0.001 {
                    state.transcript.update(start: result.range.start.seconds, end: result.range.end.seconds,
                                            text: String(result.text.characters), isFinal: result.isFinal)
                }
            }
        }
        try await analyzer.start(inputSequence: stream)
        let fileFormat = try AVAudioFile(forReading: URL(fileURLWithPath: path)).processingFormat
        let converter = try VoiceAudioConverter(from: fileFormat, to: format)
        for iteration in 1...20 {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: 2048)!
            var boundary = state.committed
            while file.framePosition < file.length {
                try file.read(into: buffer)
                let packet = try converter.convert(buffer)
                continuation.yield(AnalyzerInput(buffer: packet.buffer))
                boundary = packet.end
                try await Task.sleep(for: .milliseconds(10))
            }
            print("Finalizing utterance \(iteration) at \(boundary)")
            let began = Date()
            try await analyzer.finalize(through: CMTime(seconds: boundary - 0.001, preferredTimescale: 1_000_000))
            for _ in 0..<60 {
                if state.transcript.isFinal(through: boundary) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard state.transcript.isFinal(through: boundary) else { throw VoiceError("Final result missing") }
            let text = state.transcript.consume(through: boundary).lowercased()
            guard text.contains("mute this track"), text.contains("solo this track"), !text.contains("unmute"), state.transcript.text.isEmpty else {
                throw VoiceError("Unexpected fixture transcription: \(text)")
            }
            state.committed = boundary
            print("PASS utterance \(iteration): final result in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await results.value
    }
}
