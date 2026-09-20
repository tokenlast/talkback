// Opt-in real-microphone test. No Live connection, audio files, or transcripts.
// Compile with -D DEBUG and the same sources as continuous_speech_smoke.swift.
import Foundation
import Darwin

@main struct MicrophoneRecoverySmoke {
    @MainActor static func main() async {
        guard CommandLine.arguments.contains("--microphone") else {
            print("Pass --microphone to explicitly test physical input recovery.")
            exit(2)
        }
        let controller = DictationController()
        var starts = 0
        var recoveredAt: TimeInterval?
        var failed = false
        controller.onStatus = { status in
            guard status == "Listening" else { return }
            starts += 1
            if starts == 1 { controller.simulateInputStopForTesting() }
            if starts == 2 { recoveredAt = ProcessInfo.processInfo.systemUptime }
        }
        controller.onError = { failed = true; print("Input error: \($0)") }
        controller.start(language: .en)
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(100))
            if failed { break }
            // Stay beyond the three-second input watchdog to rule out a stale
            // queued buffer being mistaken for sustained resumed capture.
            if let recoveredAt, ProcessInfo.processInfo.systemUptime - recoveredAt >= 4 {
                controller.stop()
                print("PASS: physical input resumed after a stopped-engine configuration notification.")
                return
            }
        }
        controller.stop()
        print("FAIL: did not receive physical input before and after recovery.")
        exit(1)
    }
}
