@preconcurrency import AVFoundation
import Foundation
import NodchCore
import Speech

enum VoiceEvent: Equatable {
    /// Listening, in this language (BCP 47).
    case started(language: String)
    case unavailable(VoiceHint)
    case heard(String, final: Bool)
    /// 0…1, a few times a second while listening.
    case level(Float)
    /// After `stop(finalize: true)`: the last words are in.
    case finished
    case silence(noSpeech: Bool)
}

/// Where the quick prompt's voice comes from. Events arrive on the main actor, only for the latest `start`.
@MainActor protocol VoiceSource: AnyObject {
    func start(_ events: @escaping @MainActor (VoiceEvent) -> Void)
    /// The microphone is released before this returns. `finalize`: the words already heard still come in, then
    /// `.finished`; otherwise nothing more arrives.
    func stop(finalize: Bool)
    /// Gets ready for the next `start` without the microphone: no permission asked, nothing recorded.
    func prepare()
}

extension VoiceSource {
    func prepare() {}
}

/// The microphone through AVAudioEngine into `TranscriptionRun`. Every step of starting checks that it is still
/// wanted, so a prompt closed while permission or the model was being checked never turns the microphone on.
@MainActor
final class MicrophoneVoice: VoiceSource {
    private var generation = 0
    private var events: (@MainActor (VoiceEvent) -> Void)?
    private var starting: Task<Void, Never>?
    private var engine: Microphone?
    private var run: TranscriptionRun?
    /// The run whose results are delivered: the live one, or the one finalizing after Return.
    private var delivering: TranscriptionRun?
    /// Hands the transcriber's results to `events`; it ends when the run finishes or is cancelled.
    private var reading: Task<Void, Never>?
    private var meter: LevelMeter?
    private var meterTimer: Timer?
    private var activity: VoiceActivity?
    /// Speech models on their way, by locale: one request each, also when the language changes mid-download.
    private var downloading: Set<String> = []
    /// How long Return waits for the last words before sending what it has.
    static let finalizeLimit: Duration = .milliseconds(1500)

    /// Resolves the language and has macOS install or reserve its speech model in the background, so the first
    /// ⌥Space after launch (or after another language was chosen) does not wait for it. Speech only: the microphone
    /// and its permission are left alone until `start`.
    func prepare() {
        Task { [weak self] in
            guard let locale = await SpeechSupport.locale() else { return }
            if case .missing(let request) = await SpeechSupport.assets(for: SpeechSupport.transcriber(locale)) {
                self?.download(request, for: locale)
            }
        }
    }

    /// Apple's free download, once at a time. Often the model is on the Mac already and only needs reserving for
    /// nodch, which takes a moment; a real download goes on in the background while the prompt works with the keyboard.
    private func download(_ request: AssetInstallationRequest?, for locale: Locale) {
        let id = locale.identifier(.bcp47)
        guard let request, !downloading.contains(id) else { return }
        downloading.insert(id)
        Task { [weak self] in
            try? await request.downloadAndInstall()
            self?.downloading.remove(id)
        }
    }

    func start(_ events: @escaping @MainActor (VoiceEvent) -> Void) {
        stop(finalize: false)
        generation += 1
        self.events = events
        let generation = generation
        starting = Task { [weak self] in await self?.begin(generation) }
    }

    func stop(finalize: Bool) {
        generation += 1
        starting?.cancel()
        starting = nil
        releaseMicrophone()
        let run = run, reading = reading
        self.run = nil
        self.reading = nil
        guard finalize else {
            delivering = nil
            events = nil
            if let run { Task { await run.cancel() } }
            return
        }
        guard let run else {
            // Return before the microphone was on: nothing to finalize.
            let events = events
            self.events = nil
            delivering = nil
            Task { @MainActor in events?(.finished) }
            return
        }
        delivering = run
        Task { @MainActor [weak self] in
            let limit = Task { try? await Task.sleep(for: Self.finalizeLimit); await run.cancel() }
            try? await run.finish()
            // The last final words may still be on their way to `events`.
            await reading?.value
            limit.cancel()
            guard let self, delivering === run else { return }
            delivering = nil
            let events = events
            self.events = nil
            events?(.finished)
        }
    }

    private func releaseMicrophone() {
        meterTimer?.invalidate()
        meterTimer = nil
        meter = nil
        activity = nil
        guard let engine else { return }
        self.engine = nil
        // Stopping the hardware takes a moment too; the card closes without waiting for it.
        Task.detached { engine.release() }
    }

    private func begin(_ generation: Int) async {
        func wanted() -> Bool { generation == self.generation && !Task.isCancelled }
        func fail(_ hint: VoiceHint) {
            guard wanted() else { return }
            let events = events
            self.events = nil
            events?(.unavailable(hint))
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            // macOS asks once; a refusal is final until the person changes it in System Settings.
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return fail(.microphoneDenied) }
        default: return fail(.microphoneDenied)
        }
        // No lookup of the default capture device here: it took seconds on the first press after launch, and an
        // input without channels below says the same.
        guard wanted() else { return }
        guard let locale = await SpeechSupport.locale() else { return fail(.speechUnavailable) }
        let probe = SpeechSupport.transcriber(locale)
        switch await SpeechSupport.assets(for: probe) {
        case .installed: break
        case .unsupported: return fail(.speechUnavailable)
        case .missing(let request):
            download(request, for: locale)
            var installed = false
            for _ in 0..<12 where !installed {
                try? await Task.sleep(for: .milliseconds(250))
                guard wanted() else { return }
                installed = await AssetInventory.status(forModules: [probe]) == .installed
            }
            guard installed else { return fail(.preparing) }
        }
        guard wanted() else { return }
        // The microphone starts off the main thread: creating the input and `start()` take about half a second of
        // hardware, and on the main thread they froze the card's opening animation for that long.
        let feed = PendingFeed()
        let meter = LevelMeter()
        let opened = await Task.detached { Microphone.open(tap: Self.tap(feed, meter: meter)) }.value
        guard let engine = opened else { return fail(.noMicrophone) }
        guard wanted() else { Task.detached { engine.release() }; return }
        // The analyzer is built while the hardware starts; what the microphone hears meanwhile waits in `feed` and
        // goes to the analyzer first, so no word is lost.
        async let building = TranscriptionRun(locale: locale, source: engine.format)
        let started = await Task.detached { engine.start() }.value
        guard started, wanted() else {
            Task.detached { engine.release() }
            if let run = try? await building { await run.cancel() }
            if !started { fail(.failed) }
            return
        }
        // From here `stop` turns the microphone off, also while the analyzer is still being built.
        self.engine = engine
        let run: TranscriptionRun
        do { run = try await building } catch {
            guard wanted() else { return }
            releaseMicrophone()
            return fail(.failed)
        }
        guard wanted() else { await run.cancel(); return }
        feed.attach(run)
        self.run = run
        self.meter = meter
        activity = VoiceActivity(started: ProcessInfo.processInfo.systemUptime)
        delivering = run
        reading = Task { @MainActor [weak self] in
            do {
                for try await result in run.transcriber.results {
                    guard let self, delivering === run else { return }
                    let words = String(result.text.characters)
                    activity?.words(words, at: ProcessInfo.processInfo.systemUptime)
                    events?(.heard(words, final: result.isFinal))
                }
            } catch {}
            // Ended while still listening (an error, or the analyzer gave up): the microphone goes off and the card
            // says so, instead of showing "Listening" over a dead transcriber. After `stop` this is not the run.
            guard let self, self.run === run else { return }
            recognitionEnded(run)
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let meter = self.meter else { return }
                let level = meter.take()
                self.events?(.level(level))
                if let noSpeech = self.activity?.sample(level: level, at: ProcessInfo.processInfo.systemUptime) {
                    self.events?(.silence(noSpeech: noSpeech))
                }
            }
        }
        events?(.started(language: locale.identifier(.bcp47)))
    }

    private func recognitionEnded(_ run: TranscriptionRun) {
        releaseMicrophone()
        self.run = nil
        reading = nil
        delivering = nil
        let events = events
        self.events = nil
        Task { await run.cancel() }
        events?(.unavailable(.failed))
    }

    /// The audio thread calls this block, not the main thread: built outside the main actor, or Swift 6 traps.
    private nonisolated static func tap(_ feed: PendingFeed, meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feed.add(buffer)
            meter.add(buffer)
        }
    }
}

/// The engine and its input, used off the main thread only while starting and stopping; nothing touches it at the
/// same time (the main actor holds it only in between).
private final class Microphone: @unchecked Sendable {
    let engine: AVAudioEngine
    let format: AVAudioFormat

    private init(engine: AVAudioEngine, format: AVAudioFormat) {
        self.engine = engine
        self.format = format
    }

    /// The input with the tap installed and the engine prepared; nil when there is no input with sound.
    static func open(tap: @escaping AVAudioNodeTapBlock) -> Microphone? {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return nil }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: tap)
        engine.prepare()
        return Microphone(engine: engine, format: format)
    }

    func start() -> Bool {
        do {
            try engine.start()
            return true
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            return false
        }
    }

    func release() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Between the microphone and the analyzer: buffers heard before the analyzer is ready are kept (copied, the engine
/// reuses its own) and handed over first, in order. Up to about ten seconds; the analyzer is usually there in well
/// under one.
private final class PendingFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var run: TranscriptionRun?
    private var waiting: [AVAudioPCMBuffer] = []

    func add(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            if let run {
                run.feed(buffer)
            } else if waiting.count < 250, let copy = buffer.copy() as? AVAudioPCMBuffer {
                waiting.append(copy)
            }
        }
    }

    func attach(_ run: TranscriptionRun) {
        lock.withLock {
            for buffer in waiting { run.feed(buffer) }
            waiting = []
            self.run = run
        }
    }
}

/// The loudest moment since it was last read, as 0…1 on a speech-friendly scale (-50 dB … -10 dB).
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        let level = min(1, max(0, (db + 50) / 40))
        lock.withLock { peak = max(peak, level) }
    }

    func take() -> Float {
        lock.withLock {
            defer { peak = 0 }
            return peak
        }
    }
}
