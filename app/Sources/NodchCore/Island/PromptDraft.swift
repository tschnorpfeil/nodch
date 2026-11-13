import Foundation

// The quick prompt's decisions, pure so they are checkable: when the microphone is on, what the person's first
// keystroke does to it, what Return sends and when, and which dropped files become attachments. The app turns the
// returned `PromptEffect`s into microphone, upload and send calls and reports back what happened.

/// Why voice input is off by itself. The card says so in one quiet line and works with the keyboard.
public enum VoiceHint: Equatable, Sendable {
    case microphoneDenied, noMicrophone, speechUnavailable, preparing, failed, noSpeech

    public var text: String {
        switch self {
        case .microphoneDenied: "Voice is off: allow nodch in System Settings › Privacy › Microphone."
        case .noMicrophone: "Voice is off: no microphone found."
        case .speechUnavailable: "Voice isn’t available for this language."
        case .preparing: "Voice is getting ready: macOS is loading the speech model."
        case .failed: "Voice is off: the microphone didn’t start."
        case .noSpeech: "No speech heard. Try again or type."
        }
    }
}

public enum VoiceState: Equatable, Sendable {
    case off
    /// Asked for: permission, speech model and microphone are being checked.
    case starting
    case listening
    /// The microphone is off and the last words are being finalized.
    case finishing
    case unavailable(VoiceHint)

    /// The microphone is on, or about to be.
    public var isActive: Bool { self == .starting || self == .listening }
}

/// How the prompt came up: only the shortcut starts with the microphone on.
public enum PromptOpenCause: Equatable, Sendable { case hotkey, click, drop }

/// A file the person dropped, as the app found it on disk.
public struct DroppedFile: Equatable, Sendable {
    public var url: URL
    public var isDirectory: Bool
    public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
}

/// One chip under the field: a dropped file on its way to Nod, uploaded, or refused with the reason.
public struct PromptAttachment: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        case uploading
        case ready(NodAttachment)
        case failed(String)
    }
    public let id: Int
    public let file: URL
    public var status: Status
    public var name: String { file.lastPathComponent }

    public init(id: Int, file: URL, status: Status) { self.id = id; self.file = file; self.status = status }
}

public enum PromptEffect: Equatable, Sendable {
    case startVoice
    /// Off with the microphone. `finalize`: the transcriber still turns the audio it has into final words and then
    /// reports `voiceFinished()`; otherwise whatever it still hears is dropped.
    case stopVoice(finalize: Bool)
    case upload(id: Int, file: URL)
    case send(prompt: String, attachments: [NodAttachment])
}

public struct PromptDraft: Equatable, Sendable {
    public static let maxAttachments = 10

    /// What was typed plus the finalized transcript.
    public private(set) var text = ""
    /// The words still being recognized; they follow `text` in the field.
    public private(set) var volatile = ""
    public private(set) var voice: VoiceState = .off
    /// What the focused field really holds, as last seen: when the microphone went on, then whenever the card pushed
    /// the words into the field's editor. Nil when unknown.
    public private(set) var fieldText: String?
    public private(set) var attachments: [PromptAttachment] = []
    /// A send is out; the field and Return wait for it.
    public private(set) var sending = false
    /// The last send failed: the text stays with this under it.
    public private(set) var error: String?
    /// A quiet line under the field: a drop that left something out, or why Return waits.
    public private(set) var notice: String?
    /// Names the send that is out. A discarded draft's send that finishes late carries an older token and is ignored.
    public private(set) var sendToken = 0
    public private(set) var voiceReady = false
    private var sendAfterFinish = false
    private var noSpeech = false
    private var heardSpeech = false
    private var nextID = 1

    public init(text: String = "") { self.text = text }

    /// What the field shows.
    public var display: String { Self.join(text, volatile) }
    /// While the microphone is on, the card shows the words itself instead of relying on the focused field, which
    /// may not take changes from outside while it is being edited: `heard` bright, `hearing` (still being recognized,
    /// with the space before it) dimmed. Together they are `display`.
    public var live: (heard: String, hearing: String) { (text, String(display.dropFirst(text.count))) }
    public var ready: [NodAttachment] {
        attachments.compactMap { if case .ready(let file) = $0.status { file } else { nil } }
    }
    public var uploading: Bool { attachments.contains { $0.status == .uploading } }
    /// Escape would throw something away: the hints say "discard" then, "close" otherwise.
    public var discardsOnEscape: Bool { !display.isEmpty || !attachments.isEmpty }
    private var trimmed: String { display.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Return would send (or, while listening, stop the microphone and then send).
    public var canSend: Bool {
        !sending && voice != .finishing && !uploading && (!trimmed.isEmpty || !ready.isEmpty)
    }

    // MARK: Opening and closing

    /// The prompt came up. The shortcut turns the microphone on; a click or a drop leaves it as it is, which is off
    /// for a prompt that was closed.
    public mutating func open(_ cause: PromptOpenCause) -> [PromptEffect] {
        error = nil
        notice = nil
        return cause == .hotkey ? startVoice() : []
    }

    /// The card closed, however that happened: the microphone goes off at once and the words heard so far stay.
    /// A send that waited for the last words is called off; nothing goes out without the card.
    public mutating func closed() -> [PromptEffect] {
        let effects: [PromptEffect] = voice.isActive || voice == .finishing ? [.stopVoice(finalize: false)] : []
        keepVolatile()
        voice = .off
        notice = nil
        return effects
    }

    /// Escape: the microphone goes off and everything in the prompt is discarded.
    public mutating func escape() -> [PromptEffect] {
        let effects: [PromptEffect] = voice.isActive || voice == .finishing ? [.stopVoice(finalize: false)] : []
        self = PromptDraft(continuing: nextID)
        return effects
    }

    // MARK: Voice

    public mutating func startVoice() -> [PromptEffect] {
        guard !sending, voice != .finishing, !voice.isActive else { return [] }
        voice = .starting
        voiceReady = false
        noSpeech = false
        heardSpeech = false
        fieldText = display
        return [.startVoice]
    }

    /// The microphone button.
    public mutating func toggleVoice() -> [PromptEffect] {
        guard voice.isActive else { return startVoice() }
        return finishVoice()
    }

    /// Stop listening and finalize the words without sending.
    public mutating func finishVoice(noSpeech: Bool = false) -> [PromptEffect] {
        guard voice.isActive else { return [] }
        self.noSpeech = noSpeech
        sendAfterFinish = false
        voice = .finishing
        return [.stopVoice(finalize: true)]
    }

    /// Another dictation language was chosen. A microphone that is on, or that the old language kept off, starts
    /// over in the new one; the words heard so far stay. Otherwise it applies the next time.
    public mutating func languageChanged() -> [PromptEffect] {
        switch voice {
        case .starting, .listening:
            keepVolatile()
            voice = .starting
            return [.stopVoice(finalize: false), .startVoice]
        case .unavailable(.speechUnavailable), .unavailable(.preparing):
            voice = .off
            return startVoice()
        default:
            return []
        }
    }

    /// The card put `shown` into the focused field's editor (or found it there).
    public mutating func fieldShows(_ shown: String) { fieldText = shown }

    public mutating func voiceStarted() {
        if voice == .starting { voice = .listening }
    }

    /// The microphone or the speech model is not there: the prompt goes on with the keyboard.
    public mutating func voiceUnavailable(_ hint: VoiceHint) {
        guard voice.isActive else { return }
        keepVolatile()
        voice = .unavailable(hint)
    }

    /// Words from the transcriber. Volatile ones replace each other; final ones are kept.
    public mutating func heard(_ words: String, final: Bool) {
        guard voice == .listening || voice == .finishing else { return }
        if !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { heardSpeech = true }
        if final {
            text = Self.join(text, words)
            volatile = ""
        } else {
            volatile = words.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The person edited the field. The first keystroke while the microphone is on turns it off and keeps the
    /// transcript, so they go on typing where the voice left off.
    public mutating func typed(_ value: String) -> [PromptEffect] {
        guard value != display, !sending else { return [] }
        let takingOver = voice.isActive || voice == .finishing
        let effects: [PromptEffect] = takingOver ? [.stopVoice(finalize: false)] : []
        if takingOver {
            voice = .off
            voiceReady = false
            sendAfterFinish = false
            text = Self.takeOver(display, fieldHad: fieldText ?? display, edited: value)
            volatile = ""
            return effects
        }
        text = value
        volatile = ""
        if notice == Self.waitsForUploads { notice = nil }
        return effects
    }

    // MARK: Sending

    /// Return. While the microphone is on it goes off first and the prompt goes out once the last words are in
    /// (`voiceFinished`). Never more than one send for one Return; nothing while an upload is still running.
    public mutating func submit() -> [PromptEffect] {
        guard !sending else { return [] }
        if uploading { notice = Self.waitsForUploads; return [] }
        if voice == .finishing { sendAfterFinish = true; return [] }
        // Before the first words show, the microphone may already have heard some: finalize, then send what came.
        if voice.isActive {
            voice = .finishing
            sendAfterFinish = true
            return [.stopVoice(finalize: true)]
        }
        return send()
    }

    /// The transcriber has finalized; send only if Return explicitly requested it.
    public mutating func voiceFinished() -> [PromptEffect] {
        guard voice == .finishing else { return [] }
        keepVolatile()
        voice = noSpeech && !heardSpeech ? .unavailable(.noSpeech) : .off
        voiceReady = voice == .off && !sendAfterFinish
        noSpeech = false
        if sendAfterFinish {
            sendAfterFinish = false
            return send()
        }
        return []
    }

    private mutating func send() -> [PromptEffect] {
        let prompt = trimmed, files = ready
        guard !uploading, !prompt.isEmpty || !files.isEmpty else { return [] }
        sending = true
        sendToken = nextID
        nextID += 1
        error = nil
        notice = nil
        return [.send(prompt: prompt, attachments: files)]
    }

    /// A click on one of Nod's choices goes out like a send: the microphone goes off (its words stay), the field and
    /// Return wait, and the outcome lands only on this draft. Nil while another send is out.
    public mutating func answerChoice() -> [PromptEffect]? {
        guard !sending else { return nil }
        let stopsVoice = voice.isActive || voice == .finishing
        let effects: [PromptEffect] = stopsVoice ? [.stopVoice(finalize: false)] : []
        keepVolatile()
        if stopsVoice { voice = .off }
        sendAfterFinish = false
        voiceReady = false
        sending = true
        sendToken = nextID
        nextID += 1
        error = nil
        notice = nil
        return effects
    }

    /// Nod took a choice that went without the field's words: the field opens again with them.
    public mutating func answeredKeepingText(token: Int) {
        guard sending, token == sendToken else { return }
        sending = false
    }

    /// Nod took the message: the prompt starts empty next time. False when no send was out (it was discarded).
    /// `token`: the `sendToken` the send went out with; nil means the current one.
    public mutating func sent(token: Int? = nil) -> Bool {
        guard sending, token ?? sendToken == sendToken else { return false }
        self = PromptDraft(continuing: nextID)
        return true
    }

    public mutating func sendFailed(_ message: String, token: Int? = nil) {
        guard sending, token ?? sendToken == sendToken else { return }
        sending = false
        error = message
    }

    // MARK: Attachments

    public static let waitsForUploads = "Return sends once the files are uploaded."
    public static let folderRefused = "Folders can’t be attached. Drop the files inside instead."

    /// Which of the dropped files become chips: no folders, none twice, at most `maxAttachments` in all.
    public static func accept(_ files: [DroppedFile], existing: [URL] = []) -> (accepted: [URL], notice: String?) {
        var accepted: [URL] = [], seen = Set(existing.map(\.standardizedFileURL)), folders = 0, over = 0
        for file in files {
            if file.isDirectory { folders += 1; continue }
            guard seen.insert(file.url.standardizedFileURL).inserted else { continue }
            if existing.count + accepted.count < maxAttachments { accepted.append(file.url) } else { over += 1 }
        }
        var notes: [String] = []
        if folders > 0 { notes.append(folderRefused) }
        if over > 0 { notes.append("Up to \(maxAttachments) files: \(over) left out.") }
        return (accepted, notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    /// Files dropped on the island: a chip for each one that is accepted, uploading at once.
    public mutating func drop(_ files: [DroppedFile]) -> [PromptEffect] {
        guard !sending else { return [] }
        let (accepted, notice) = Self.accept(files, existing: attachments.map(\.file))
        self.notice = notice
        error = nil
        return accepted.map { url in
            let id = nextID
            nextID += 1
            attachments.append(PromptAttachment(id: id, file: url, status: .uploading))
            return .upload(id: id, file: url)
        }
    }

    public mutating func uploaded(_ id: Int, as file: NodAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == id }), attachments[index].status == .uploading else { return }
        attachments[index].status = .ready(file)
        if !uploading, notice == Self.waitsForUploads { notice = nil }
    }

    public mutating func uploadFailed(_ id: Int, reason: String) {
        guard let index = attachments.firstIndex(where: { $0.id == id }), attachments[index].status == .uploading else { return }
        attachments[index].status = .failed(reason)
        if !uploading, notice == Self.waitsForUploads { notice = nil }
    }

    /// The chip's ×. An upload still running finishes on its own; its result is ignored.
    public mutating func remove(_ id: Int) {
        guard !sending else { return }
        attachments.removeAll { $0.id == id }
        if !uploading, notice == Self.waitsForUploads { notice = nil }
    }

    // MARK: Text

    /// Appends recognized words to what is there, with one space between them.
    public static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return head }
        guard let last = head.last else { return tail }
        if last.isWhitespace || tail.first.map({ ",.;:!?)".contains($0) }) == true { return head + tail }
        return head + " " + tail
    }

    /// The first keystroke while the microphone was on. `fieldHad` is what the focused field really held before it:
    /// the field does not always take the transcriber's words while it is being edited. When it held the whole
    /// dictation, the edit is taken as it is (typing, Backspace, a selection replaced, a paste). When it was behind,
    /// the edit was made on older text the person could not see; what it added goes at the end of everything heard,
    /// where they saw the caret, and what it removed from that older text is ignored.
    public static func takeOver(_ heard: String, fieldHad: String, edited: String) -> String {
        if fieldHad == heard { return edited }
        let old = Array(fieldHad), new = Array(edited)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        return heard + String(new[prefix..<(new.count - suffix)])
    }

    private mutating func keepVolatile() {
        text = display
        volatile = ""
    }

    private init(continuing nextID: Int) { self.nextID = nextID }
}
