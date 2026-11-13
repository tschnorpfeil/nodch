@preconcurrency import AVFoundation
import Foundation
import NodchCore
import Speech

enum VoiceEvent: Equatable {
    case started
    case unavailable(VoiceHint)
    case heard(String, final: Bool)
    /// 0…1, a few times a second while listening.
    case level(Float)
    /// After `stop(finalize: true)`: the last words are in.
    case finished
}

/// Where the quick prompt's voice comes from. Events arrive on the main actor, only for the latest `start`.
@MainActor protocol VoiceSource: AnyObject {
    func start(_ events: @escaping @MainActor (VoiceEvent) -> Void)
    /// The microphone is released before this returns. `finalize`: the words already heard still come in, then
    /// `.finished`; otherwise nothing more arrives.
    func stop(finalize: Bool)
}

/// The microphone through AVAudioEngine into `TranscriptionRun`. Every step of starting checks that it is still
/// wanted, so a prompt closed while permission or the model was being checked never turns the microphone on.
@MainActor
final class MicrophoneVoice: VoiceSource {
    private var generation = 0
    private var events: (@MainActor (VoiceEvent) -> Void)?
    private var starting: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var run: TranscriptionRun?
    /// The run whose results are delivered: the live one, or the one finalizing after Return.
    private var delivering: TranscriptionRun?
    /// Hands the transcriber's results to `events`; it ends when the run finishes or is cancelled.
    private var reading: Task<Void, Never>?
    private var meter: LevelMeter?
    private var meterTimer: Timer?
    private var downloading = false
    /// How long Return waits for the last words before sending what it has.
    static let finalizeLimit: Duration = .milliseconds(1500)

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
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
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
        guard wanted() else { return }
        guard AVCaptureDevice.default(for: .audio) != nil else { return fail(.noMicrophone) }
        guard let locale = await SpeechSupport.locale() else { return fail(.speechUnavailable) }
        let probe = SpeechSupport.transcriber(locale)
        switch await SpeechSupport.assets(for: probe) {
        case .installed: break
        case .unsupported: return fail(.speechUnavailable)
        case .missing(let request):
            // Apple's free download. Often the model is on the Mac already and only needs reserving for nodch, which
            // takes a moment; a real download goes on in the background while this prompt works with the keyboard.
            if let request, !downloading {
                downloading = true
                Task { [weak self] in
                    try? await request.downloadAndInstall()
                    self?.downloading = false
                }
            }
            var installed = false
            for _ in 0..<12 where !installed {
                try? await Task.sleep(for: .milliseconds(250))
                guard wanted() else { return }
                installed = await AssetInventory.status(forModules: [probe]) == .installed
            }
            guard installed else { return fail(.preparing) }
        }
        guard wanted() else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return fail(.noMicrophone) }
        let run: TranscriptionRun
        do { run = try await TranscriptionRun(locale: locale, source: format) } catch { return fail(.failed) }
        guard wanted() else { await run.cancel(); return }
        let meter = LevelMeter()
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.tap(run, meter: meter))
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            await run.cancel()
            return fail(.failed)
        }
        self.engine = engine
        self.run = run
        self.meter = meter
        delivering = run
        reading = Task { @MainActor [weak self] in
            do {
                for try await result in run.transcriber.results {
                    guard let self, delivering === run else { return }
                    events?(.heard(String(result.text.characters), final: result.isFinal))
                }
            } catch {}
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let meter = self.meter else { return }
                self.events?(.level(meter.take()))
            }
        }
        events?(.started)
    }

    /// The audio thread calls this block, not the main thread: built outside the main actor, or Swift 6 traps.
    private nonisolated static func tap(_ run: TranscriptionRun, meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            run.feed(buffer)
            meter.add(buffer)
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
