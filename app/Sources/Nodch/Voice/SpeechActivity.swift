@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis
import Foundation
import CoreMedia

/// Owns the classifier and its bounded, serial audio queue. The tap only copies and enqueues buffers.
final class SpeechActivity: NSObject, SNResultsObserving, @unchecked Sendable {
    private let queue = DispatchQueue(label: "nodch.speech-activity")
    private let lock = NSLock()
    private let analyzer: SNAudioStreamAnalyzer
    private let report: @Sendable (Double?, Double) -> Void
    private var active = true
    private var pending = 0
    private var offset: AVAudioFramePosition = 0
    private static let maxPending = 32

    init(format: AVAudioFormat, report: @escaping @Sendable (Double?, Double) -> Void) throws {
        self.analyzer = SNAudioStreamAnalyzer(format: format)
        self.report = report
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 16000)
        request.overlapFactor = 0
        try analyzer.add(request, withObserver: self)
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active else { lock.unlock(); return }
        guard pending < Self.maxPending, let copy = buffer.copy() as? AVAudioPCMBuffer else {
            active = false
            lock.unlock()
            report(nil, 0)
            return
        }
        let position = offset
        offset += AVAudioFramePosition(copy.frameLength)
        pending += 1
        queue.async { [self] in
            let shouldAnalyze = lock.withLock { active }
            if shouldAnalyze { analyzer.analyze(copy, atAudioFramePosition: position) }
            lock.withLock { pending -= 1 }
        }
        lock.unlock()
    }

    func cancel() {
        lock.withLock { active = false }
        queue.async { [self] in analyzer.removeAllRequests() }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard lock.withLock({ active }) else { return }
        guard let result = result as? SNClassificationResult,
              let speech = result.classification(forIdentifier: "speech") else {
            self.request(request, didFailWithError: NSError(domain: "nodch.speech-activity", code: 1))
            return
        }
        report(speech.confidence, result.timeRange.end.seconds)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        let failed = lock.withLock { () -> Bool in
            guard active else { return false }
            active = false
            return true
        }
        if failed { report(nil, 0) }
    }

    func requestDidComplete(_ request: SNRequest) {}
}

/// The tap is installed before the input format is known; configure before starting the engine.
final class SpeechActivityFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var activity: SpeechActivity?
    func set(_ activity: SpeechActivity?) { lock.withLock { self.activity = activity } }
    func add(_ buffer: AVAudioPCMBuffer) { lock.withLock { activity }?.add(buffer) }
}
