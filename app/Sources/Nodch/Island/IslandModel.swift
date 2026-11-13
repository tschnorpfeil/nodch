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
    /// When the current approval or question first showed; Approve, Decline and the choices wait out
    /// `IslandPresentation.answerGuard`. Set through `startAnswerGuard`.
    private(set) var approvalShownAt = Date.distantPast
    /// The guard still holds: those buttons show dimmed and take nothing.
    private(set) var answerGuarded = false
    @ObservationIgnored private var guardEnd: Task<Void, Never>?
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
    /// The card shows the prompt (with an answer or Nod's question above it), not a status card.
    var showsPromptCard: Bool { showsPrompt || tone == .rest || tone == .done || asking != nil }
    var showsApprovalCard: Bool { !showsPromptCard && approval != nil }
    /// What the open card offers to the keyboard (`IslandPresentation.keyAction`).
    var cardOffers: IslandPresentation.CardOffers {
        guard isOpen else { return .init() }
        guard showsPromptCard else { return .init(approval: approval != nil, stop: tone == .working) }
        let field = draft.display.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(picks: asking?.question?.multiple == true && !picked.isEmpty && field.isEmpty && !draft.sending)
    }
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
    var highlightedChoice: String?

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

    /// The card shows a new decision (or shows it again): the guard starts at `shownAt`. The buttons come back by
    /// themselves when it ends; nobody has to move the pointer.
    func startAnswerGuard(at shownAt: Date = Date()) {
        approvalShownAt = shownAt
        guardEnd?.cancel()
        let remaining = IslandPresentation.answerGuardRemaining(shownFor: Date().timeIntervalSince(shownAt))
        answerGuarded = remaining > 0
        guard remaining > 0 else { return }
        guardEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.answerGuarded = false
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
                if !finalize { voiceGeneration += 1 }
                voice?.stop(finalize: finalize)
            case .upload(let id, let file): upload(id, file)
            case .send(let prompt, let attachments): send(prompt, attachments)
            }
        }
    }

    /// The field changed under the person's hands (not by the transcriber).
    func typed(_ value: String) { highlightedChoice = nil; perform(draft.typed(value)) }
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
        // The new language's speech model gets ready in the background, also when the microphone is off now.
        voice?.prepare()
        perform(draft.languageChanged())
    }

    func loadSpeechLanguages() {
        guard speechLanguages.yours.isEmpty, speechLanguages.others.isEmpty else { return }
        Task { speechLanguages = SpeechLanguage.menu(supported: await SpeechSupport.supported(), system: Locale.preferredLanguages) }
    }

    @ObservationIgnored private var voiceGeneration = 0

    private func startVoice() {
        guard let voice else { draft.voiceUnavailable(.speechUnavailable); return }
        voiceGeneration += 1
        let generation = voiceGeneration
        voice.start { [weak self] event in
            guard let self, self.voiceGeneration == generation else { return }
            self.heard(event)
        }
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
        case .silence(let noSpeech): perform(draft.finishVoice(noSpeech: noSpeech))
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

    /// Arrow keys only move the highlight, and only while the field is empty. Return acts like a click on the
    /// highlighted choice.
    func questionKey(_ key: UInt16) -> Bool {
        guard let question = asking?.question, !draft.sending else { return false }
        if key == 125 || key == 126 {
            guard IslandPresentation.arrowsMoveChoices(field: draft.display, choices: question.choices.count) else { return false }
            highlightedChoice = IslandPresentation.nextChoice(highlightedChoice, choices: question.choices.map(\.id), down: key == 125)
            return true
        }
        guard key == 36 || key == 76, let id = highlightedChoice,
              let choice = question.choices.first(where: { $0.id == id }) else { return false }
        pick(choice)
        return true
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
                finishSend(token: token, questionID: asked.id, keepingText: text.isEmpty)
            } catch {
                failSend(error, token: token, questionID: asked.id)
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
                } else {
                    try await actions.send(prompt: prompt, attachments: attachments)
                }
                finishSend(token: token, questionID: asked?.id)
            } catch {
                failSend(error, token: token, questionID: asked?.id)
            }
        }
    }

    /// A later question can arrive before Nod acknowledges this send. Complete the old draft without closing it.
    private func finishSend(token: Int, questionID: String?, keepingText: Bool = false) {
        guard draft.sending, draft.sendToken == token else { return }
        if let questionID, asking?.id == questionID { picked = [] }
        if keepingText { draft.answeredKeepingText(token: token) } else { _ = draft.sent(token: token) }
        if let current = asking, current.id != questionID {
            if isOpen { focusToken += 1 }
        } else if !keepingText {
            onSent()
        } else if isOpen, showsPrompt {
            focusToken += 1
        }
    }

    private func failSend(_ error: Error, token: Int, questionID: String?) {
        guard draft.sending, draft.sendToken == token else { return }
        let newQuestion = asking.map { $0.id != questionID } ?? false
        let prefix = newQuestion ? (questionID == nil ? "Couldn’t send the previous message: " : "Couldn’t send the previous answer: ") : ""
        draft.sendFailed(prefix + Self.describe(error), token: token)
        if isOpen, showsPrompt { focusToken += 1 }
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
