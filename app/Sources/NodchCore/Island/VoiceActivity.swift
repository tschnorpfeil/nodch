import Foundation

/// Consumes ordered classifier windows in audio time, never wall-clock or transcript time.
public struct VoiceActivity: Sendable {
    private var nextWindow = 1
    private var pending: [Int: Double] = [:]
    private var lastSpeech: TimeInterval?
    private var ended = false
    public private(set) var failed = false

    public init() {}

    /// Returns true for no speech, false for silence after speech, nil while listening.
    public mutating func sample(confidence: Double, end: TimeInterval) -> Bool? {
        guard !ended, end.isFinite, end > 0, end < Double(Int.max) / 2 else { return nil }
        let window = Int((end * 2).rounded())
        guard window >= nextWindow else { return nil }
        guard window < nextWindow + 64 else { failed = true; return nil }
        pending[window] = confidence
        while let confidence = pending.removeValue(forKey: nextWindow) {
            let time = Double(nextWindow) / 2
            nextWindow += 1
            if confidence >= 0.5 { lastSpeech = time }
            let decision: Bool?
            if let lastSpeech {
                decision = time - lastSpeech >= 1.5 ? false : nil
            } else {
                decision = time >= 10 ? true : nil
            }
            if let decision { ended = true; pending.removeAll(); return decision }
        }
        return nil
    }
}
