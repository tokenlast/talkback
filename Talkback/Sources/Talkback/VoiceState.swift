import Foundation

struct VoiceEndpoint {
    private var lastSound: TimeInterval?
    private var lastAudio: TimeInterval?
    private var lastText: TimeInterval?
    mutating func audioArrived(at now: TimeInterval, audible: Bool) {
        lastAudio = now
        if audible { lastSound = now }
    }
    mutating func textChanged(at now: TimeInterval) { lastText = now }
    func shouldFinish(at now: TimeInterval, hasText: Bool, pause: TimeInterval = 1) -> Bool {
        guard hasText, let lastAudio, let lastText else { return false }
        return now - lastAudio < 0.3 && now - (lastSound ?? lastText) >= pause && now - lastText >= min(0.3, pause)
    }
}

struct VoiceTranscript {
    struct Segment { let start: Double; let end: Double; let text: String; let isFinal: Bool }
    private var segments: [Segment] = []
    private(set) var overflowed = false
    var hasSpeech: Bool { !segments.isEmpty }
    private(set) var finalizedThrough = 0.0
    mutating func finalize(through time: Double) {
        guard time.isFinite else { return }
        finalizedThrough = max(finalizedThrough, time)
    }
    mutating func update(start: Double, end: Double, text: String, isFinal: Bool) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        segments.removeAll { ($0.start < end && $0.end > start) || $0.start == start }
        segments.append(Segment(start: start, end: end, text: text, isFinal: isFinal))
        segments.sort { $0.start < $1.start }
        if joined(segments).count > 500 || segments.count > 32 {
            overflowed = true
            // Keep timing for the quiet boundary, never execute a truncated command.
            segments = [Segment(start: start, end: end, text: "", isFinal: isFinal)]
        }
    }
    var text: String { overflowed ? "" : joined(segments) }
    func isFinal(through end: Double) -> Bool {
        let current = segments.filter { $0.start < end }
        // A later result's watermark also finalizes earlier, unchanged partials.
        // Apple does not guarantee a replacement result with isFinal == true.
        return !current.isEmpty && current.allSatisfy {
            ($0.isFinal || $0.end <= finalizedThrough) && $0.end <= end + 0.01
        }
    }
    mutating func consume(through end: Double) -> String {
        let ready = segments.filter { $0.end <= end + 0.01 }
        segments.removeAll { $0.end <= end + 0.01 }
        let answer = overflowed ? "" : joined(ready)
        if segments.isEmpty { overflowed = false }
        return answer
    }
    private func joined(_ values: [Segment]) -> String {
        values.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }
            .joined(separator: " ")
    }
}
