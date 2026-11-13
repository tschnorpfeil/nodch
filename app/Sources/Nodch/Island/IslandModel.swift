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

    private func startVoice() {
        guard let voice else { draft.voiceUnavailable(.speechUnavailable); return }
        voice.start { [weak self] event in self?.heard(event) }
    }

    private func heard(_ event: VoiceEvent) {
        switch event {
        case .started: draft.voiceStarted()
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

    private func send(_ prompt: String, _ attachments: [NodAttachment]) {
        guard let actions = store.actions else { draft.sendFailed(Self.notConnected); return }
        let token = draft.sendToken
        Task {
            do {
                try await actions.send(prompt: prompt, attachments: attachments)
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
