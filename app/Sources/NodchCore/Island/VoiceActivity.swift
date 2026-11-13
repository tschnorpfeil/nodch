import Foundation

/// Monotonic seconds and recognizer evidence keep steady background noise from starting dictation.
public struct VoiceActivity: Sendable {
    private let started: TimeInterval
    private var lastSpeech: TimeInterval?
    private var lastRecognition: TimeInterval?
    private var ambient: Float = 0
    private var lastWords = ""

    public init(started: TimeInterval) { self.started = started }

    public mutating func words(_ words: String, at now: TimeInterval) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words != lastWords else { return }
        lastWords = words
        lastSpeech = now
        lastRecognition = now
    }

    /// Returns true for no speech, false for silence after speech, nil while listening.
    public mutating func sample(level: Float, at now: TimeInterval) -> Bool? {
        if let lastSpeech {
            if now - (lastRecognition ?? now) < 3, level > max(0.35, ambient + 0.15) { self.lastSpeech = now }
            return now - (self.lastSpeech ?? lastSpeech) >= 1.5 ? false : nil
        }
        ambient = max(ambient, level)
        return now - started >= 10 ? true : nil
    }
}
