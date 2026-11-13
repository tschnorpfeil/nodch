@preconcurrency import AVFoundation
import Foundation
import NodchCore
import Speech

/// On-device speech to text with SpeechAnalyzer and SpeechTranscriber (macOS 26). Nothing leaves the Mac: the model
/// is Apple's, downloaded once through AssetInventory. The microphone and `Nodch --transcribe` feed the same run.
enum SpeechSupport {
    static let fallback = Locale(identifier: "en-US")

    /// The system's language if the transcriber knows it, otherwise US English; nil when on-device speech is missing.
    static func locale(preferred: Locale = .current) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) { return locale }
        return await SpeechTranscriber.supportedLocale(equivalentTo: fallback)
    }

    /// Volatile results stream the words as they are heard; final ones replace them.
    static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    enum Assets {
        case installed
        /// The model can be downloaded; nil while macOS is downloading it already.
        case missing(AssetInstallationRequest?)
        case unsupported
    }

    static func assets(for transcriber: SpeechTranscriber) async -> Assets {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .installed
        case .unsupported: return .unsupported
        default: return .missing(try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]))
        }
    }
}

/// One transcription: audio buffers in any format go in, the transcriber's results come out. `feed` may be called
/// from the audio thread; everything else from one task at a time.
final class TranscriptionRun: Sendable {
    enum Failure: LocalizedError {
        case noFormat
        var errorDescription: String? { "The speech model accepts no audio format." }
    }

    let transcriber: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: BufferConverter

    /// `source`: the format of the buffers that `feed` gets.
    init(locale: Locale, source: AVAudioFormat) async throws {
        let transcriber = SpeechSupport.transcriber(locale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: source) else {
            throw Failure.noFormat
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse))
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.input = input
        converter = try BufferConverter(from: source, to: format)
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    /// No more audio: the analyzer finalizes what it has heard, then its results end.
    func finish() async throws {
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    /// Drops what is still in flight.
    func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
    }
}

/// Converts the microphone's or a file's buffers to the analyzer's format. Used from one thread at a time.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        self.target = target
        if source == target {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: target) else { throw TranscriptionRun.Failure.noFormat }
            // No priming: the first words would otherwise be shifted by the resampler's latency.
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

/// `Nodch --transcribe <audio file> [--locale <id>]`: the same transcriber as the quick prompt, on a file instead of
/// the microphone. Prints the final text. Downloads the speech model first if macOS has not yet.
enum TranscribeCommand {
    static func run(file: URL, locale identifier: String?) async -> Int32 {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write(Data("nodch: \(message)\n".utf8))
            return 1
        }
        let preferred = identifier.map(Locale.init(identifier:)) ?? .current
        guard let locale = await SpeechSupport.locale(preferred: preferred) else {
            return fail("on-device speech recognition is not available on this Mac")
        }
        if identifier != nil, locale.language.languageCode != preferred.language.languageCode {
            return fail("\(preferred.identifier) is not supported by the speech model")
        }
        FileHandle.standardError.write(Data("nodch: transcribing in \(locale.identifier)\n".utf8))
        switch await SpeechSupport.assets(for: SpeechSupport.transcriber(locale)) {
        case .installed: break
        case .unsupported: return fail("the speech model does not support \(locale.identifier)")
        case .missing(let request):
            FileHandle.standardError.write(Data("nodch: downloading the speech model for \(locale.identifier)…\n".utf8))
            if let request {
                do { try await request.downloadAndInstall() } catch { return fail("download failed: \(error.localizedDescription)") }
            } else {
                // Already on its way: wait for it, up to five minutes.
                let transcriber = SpeechSupport.transcriber(locale)
                var waited = 0
                while await AssetInventory.status(forModules: [transcriber]) != .installed {
                    guard waited < 300 else { return fail("the speech model for \(locale.identifier) did not arrive") }
                    try? await Task.sleep(for: .seconds(1))
                    waited += 1
                }
            }
        }
        let audio: AVAudioFile
        do { audio = try AVAudioFile(forReading: file) } catch { return fail("cannot read \(file.path): \(error.localizedDescription)") }
        let run: TranscriptionRun
        do { run = try await TranscriptionRun(locale: locale, source: audio.processingFormat) } catch {
            return fail("the transcriber did not start: \(error.localizedDescription)")
        }
        let collector = Task {
            var finals: [String] = []
            for try await result in run.transcriber.results where result.isFinal {
                finals.append(String(result.text.characters))
            }
            return finals.reduce("") { PromptDraft.join($0, $1) }
        }
        do {
            while audio.framePosition < audio.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096) else { break }
                try audio.read(into: buffer)
                if buffer.frameLength == 0 { break }
                run.feed(buffer)
            }
            try await run.finish()
            print(try await collector.value)
            return 0
        } catch {
            collector.cancel()
            return fail("transcription failed: \(error.localizedDescription)")
        }
    }
}
