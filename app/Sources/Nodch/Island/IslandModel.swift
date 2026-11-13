import AppKit
import NodchCore
import Observation

/// What the island's views read besides `IslandStore.state`: whether the card is open and what it shows, the quick
/// prompt (`PromptDraft`, with its voice and attachments), and actions in flight. Every call to Nod goes through
/// `store.actions`, once per explicit user action, and is never retried: a failure shows inline and waits for the person.
@MainActor @Observable final class IslandModel {
    let store: IslandStore
    /// The pointer is on the island (it reveals the resting notch's affordance and the offline wing's words).
    var hovering = false
    /// The current `.done` has shown long enough: the island reads it as rest.
    var doneExpired = false
    var isOpen = false
    /// The open card shows the quick prompt instead of the state.
    var showsPrompt = false
    /// The quick prompt: text, voice, attachments. Changed only through the methods below, which carry out what it
    /// decides (`PromptEffect`).
    var draft = PromptDraft()
    /// The microphone's level while listening, 0…1.
    var voiceLevel: Float = 0
    /// Files dragged toward or over the island.
    var dropZone = IslandDropZone.none
    /// An answer on its way: true for Approve, false for Decline.
    private(set) var answering: Bool?
    private(set) var stopping = false
    /// A failed Approve, Decline or Stop, shown in the card until the next try or another approval.
    var actionError: String?
    /// When the current approval first showed; Approve and Decline wait out `IslandPresentation.answerGuard`.
    var approvalShownAt = Date.distantPast
    /// Raised to put the keyboard in the prompt field once the card can take it.
    var focusToken = 0
    var layout = Layout()
    /// The wing's content. It stays while the wing shrinks back to rest, so the words do not vanish mid-motion.
    var shown = Shown()
    var hotkey: String? = HotkeySpec.standard.display
    /// The dictation language picked from the microphone's menu; nil follows the system.
    var speechChoice: String? = SpeechLanguage.choice(UserDefaults.standard.string(forKey: SpeechLanguage.defaultsKey))
    /// What the microphone listens in right now (BCP 47), for the placeholder.
    var listeningIn: String?
    /// The languages the on-device model offers, loaded once when the menu is first wanted.
    var speechLanguages: (yours: [String], others: [String]) = ([], [])

    struct Layout: Equatable {
        var notch = false
        /// The wing's sides after the geometry clamped them.
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        /// At the notch, open: the menu bar row's parts left and right of the housing.
        var rowLeft: CGFloat = 0
        var rowRight: CGFloat = 0
        var rowHeight: CGFloat = 0
        /// The tallest the card's content may be on this display.
        var maxContent: CGFloat = 800
    }

    struct Shown: Equatable {
        var tone: IslandTone = .rest
        var wing = IslandWing()
        var line = ""
        var since: Date?
        /// Files are dragged toward (or over) the closed island.
        var drop = IslandDropZone.none
    }

    @ObservationIgnored var onCompactClick: () -> Void = {}
    @ObservationIgnored var onCollapse: () -> Void = {}
    /// The prompt went out: the card closes and the keyboard goes back.
    @ObservationIgnored var onSent: () -> Void = {}
    @ObservationIgnored var log: (String) -> Void = { print("nodch: \($0)") }
    /// The microphone; nil (snapshots) reads as voice not available.
    @ObservationIgnored var voice: VoiceSource?

    init(store: IslandStore) { self.store = store }

    var state: IslandState { store.state }
    var tone: IslandTone { IslandPresentation.tone(store.state, doneAge: doneExpired ? .infinity : 0) }
    var line: String { IslandPresentation.line(store.state) }
    var wing: IslandWing? {
        if dropZone != .none, !isOpen { return IslandWing() }
        return IslandPresentation.wing(store.state, tone: tone, hovering: hovering && !isOpen)
    }
    /// The wing's words: while files are dragged toward the closed island, where they go.
    var wingLine: String {
        // The same words near and over: a wing that changed width under the pointer could flicker between the two.
        dropZone != .none && !isOpen ? "Drop files for Nod" : line
    }
    var sending: Bool { draft.sending }
    var approval: (PendingApproval, more: Int)? {
        if case .needsYou(let approval, let more) = store.state { (approval, more) } else { nil }
    }
    var activity: WorkActivity? { if case .working(let activity) = store.state { activity } else { nil } }
    /// Nod's question that waits for the person's pick or own words.
    var asking: NodAnswer? { if case .asks(let answer) = store.state { answer } else { nil } }
    /// The answer above the prompt field: the open question, or the last answer while a follow-up still reads in context.
    var shownAnswer: NodAnswer? { IslandPresentation.shownAnswer(store.answer, state: store.state) }
    /// Choices ticked on a question that takes several.
    var picked: Set<String> = []

    static let notConnected = "nodch isn’t connected to Nod yet."

    func answer(approved: Bool) {
        guard answering == nil, let (approval, _) = approval else { return }
        guard IslandPresentation.acceptsAnswer(shownFor: Date().timeIntervalSince(approvalShownAt)) else { return }
        guard let actions = store.actions else { actionError = Self.notConnected; return }
        answering = approved
        actionError = nil
        Task {
            do { try await actions.answer(approval: approval, approved: approved) } catch {
                actionError = (approved ? "Couldn’t approve: " : "Couldn’t decline: ") + Self.describe(error)
            }
            answering = nil
        }
    }

    func stop() {
        guard !stopping else { return }
        guard let actions = store.actions else { actionError = Self.notConnected; return }
        stopping = true
        actionError = nil
        Task {
            do { try await actions.stop() } catch { actionError = "Couldn’t stop: " + Self.describe(error) }
            stopping = false
        }
    }

    // MARK: Quick prompt

    /// Carries out what the draft decided: the microphone, uploads and the one send.
    func perform(_ effects: [PromptEffect]) {
        for effect in effects {
            switch effect {
            case .startVoice: startVoice()
            case .stopVoice(let finalize):
                voiceLevel = 0
                voice?.stop(finalize: finalize)
            case .upload(let id, let file): upload(id, file)
            case .send(let prompt, let attachments): send(prompt, attachments)
            }
        }
    }

    /// The field changed under the person's hands (not by the transcriber).
    func typed(_ value: String) { perform(draft.typed(value)) }
    func toggleVoice() { perform(draft.toggleVoice()) }
    /// Return: sends once, after the microphone is off. On success the card closes; on failure the text stays with
    /// the error under it.
    func submitPrompt() { perform(draft.submit()) }
    func dropped(_ files: [DroppedFile]) { perform(draft.drop(files)) }
    func removeAttachment(_ id: Int) { draft.remove(id) }

    /// From the microphone's menu: nil follows the system again. A microphone that is on starts over in it.
    func chooseSpeechLanguage(_ id: String?) {
        guard id != speechChoice else { return }
        speechChoice = id
        if let id { UserDefaults.standard.set(id, forKey: SpeechLanguage.defaultsKey) } else {
            UserDefaults.standard.removeObject(forKey: SpeechLanguage.defaultsKey)
        }
        perform(draft.languageChanged())
    }

    func loadSpeechLanguages() {
        guard speechLanguages.yours.isEmpty, speechLanguages.others.isEmpty else { return }
        Task { speechLanguages = SpeechLanguage.menu(supported: await SpeechSupport.supported(), system: Locale.preferredLanguages) }
    }

    private func startVoice() {
        guard let voice else { draft.voiceUnavailable(.speechUnavailable); return }
        voice.start { [weak self] event in self?.heard(event) }
    }

    private func heard(_ event: VoiceEvent) {
        switch event {
        case .started(let language):
            listeningIn = language
            draft.voiceStarted()
        case .unavailable(let hint):
            voiceLevel = 0
            draft.voiceUnavailable(hint)
        case .heard(let words, let final): draft.heard(words, final: final)
        case .level(let level): voiceLevel = draft.voice == .listening ? level : 0
        case .finished:
            voiceLevel = 0
            perform(draft.voiceFinished())
        }
    }

    private func upload(_ id: Int, _ file: URL) {
        guard let actions = store.actions else { draft.uploadFailed(id, reason: Self.notConnected); return }
        Task {
            do { draft.uploaded(id, as: try await actions.upload(file: file)) } catch {
                draft.uploadFailed(id, reason: Self.describe(error))
            }
        }
    }

    /// A choice on Nod's question. On a single-choice question the click is the answer; otherwise it ticks the choice.
    func pick(_ choice: NodQuestion.Choice) {
        guard let asked = asking, let question = asked.question, !draft.sending else { return }
        // A card that just appeared by itself ignores clicks for a moment, like an approval.
        guard IslandPresentation.acceptsAnswer(shownFor: Date().timeIntervalSince(approvalShownAt)) else { return }
        guard question.multiple else { answer(asked, choices: [choice], withWords: false); return }
        if picked.contains(choice.id) { picked.remove(choice.id) } else { picked.insert(choice.id) }
    }

    /// Sends the ticked choices of a multiple-choice question, with the words in the field if there are any.
    func sendPicks() {
        guard let asked = asking, let question = asked.question, !picked.isEmpty else { return }
        answer(asked, choices: question.choices.filter { picked.contains($0.id) }, withWords: true)
    }

    /// One answer to Nod's question, from one click, through the draft's send lifecycle: nothing else goes out while it
    /// is on its way, a failure shows under the field, and only the words that went with it are cleared.
    private func answer(_ asked: NodAnswer, choices: [NodQuestion.Choice], withWords: Bool) {
        guard let effects = draft.answerChoice() else { return }
        perform(effects)
        let token = draft.sendToken
        let text = withWords ? draft.display.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard let actions = store.actions else { draft.sendFailed(Self.notConnected, token: token); return }
        Task {
            do {
                try await actions.answer(question: asked, choices: choices, text: text)
                picked = []
                if text.isEmpty { draft.answeredKeepingText(token: token) } else if draft.sent(token: token) { onSent() }
            } catch {
                draft.sendFailed(Self.describe(error), token: token)
            }
        }
    }

    private func send(_ prompt: String, _ attachments: [NodAttachment]) {
        guard let actions = store.actions else { draft.sendFailed(Self.notConnected); return }
        let token = draft.sendToken
        // Words typed under Nod's open question answer it, as Nod's own composer does; files go out as a new message.
        let asked = attachments.isEmpty ? asking : nil
        let choices = asked?.question.map { question in question.choices.filter { picked.contains($0.id) } } ?? []
        Task {
            do {
                if let asked {
                    try await actions.answer(question: asked, choices: asked.question?.multiple == true ? choices : [], text: prompt)
                    picked = []
                } else {
                    try await actions.send(prompt: prompt, attachments: attachments)
                }
                if draft.sent(token: token) { onSent() }
            } catch {
                draft.sendFailed(Self.describe(error), token: token)
            }
        }
    }

    func openNod(path: String = "/") {
        guard let actions = store.actions else { log("Open Nod \(path): \(Self.notConnected)"); return }
        actions.openNod(path: path)
    }

    static func describe(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.isEmpty ? "Something went wrong." : text
    }
}
