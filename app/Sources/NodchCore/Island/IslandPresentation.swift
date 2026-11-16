import Foundation

/// How the island reads an `IslandState`: one tone, one line for the wing, and what the wing carries. Pure, so the
/// decisions the UI takes (what opens by itself, what takes the keyboard, when "done" goes back to rest) are checkable.
public enum IslandTone: Equatable, Sendable {
    case rest, offline, working, needsYou, done, failed
}

/// What the compact wing (or pill) carries besides its line.
public struct IslandWing: Equatable, Sendable {
    /// The leading glyph: a status sign, a spinner, or the "connected" dot when the resting notch is hovered.
    public var showsGlyph = true
    /// The words (hidden for an offline island until it is hovered).
    public var showsLine = true
    /// Working: the elapsed time and a Stop control on the trailing side.
    public var showsElapsed = false
    public var showsStop = false
    /// The resting notch under the pointer: the shortcut that opens the quick prompt.
    public var showsHint = false
    /// Further pending approvals ("+2").
    public var more = 0
    /// Needs you: a chevron says the wing opens into the card.
    public var showsChevron = false
    /// Done: how long the turn took, on the trailing side, in the same "m:ss" the working counter ended on.
    public var showsTook = false

    public init(showsGlyph: Bool = true, showsLine: Bool = true, showsElapsed: Bool = false, showsStop: Bool = false,
                showsHint: Bool = false, more: Int = 0, showsChevron: Bool = false, showsTook: Bool = false) {
        self.showsGlyph = showsGlyph; self.showsLine = showsLine; self.showsElapsed = showsElapsed; self.showsStop = showsStop
        self.showsHint = showsHint; self.more = more; self.showsChevron = showsChevron
        self.showsTook = showsTook
    }
}

public enum IslandPresentation {
    /// How long "done" shows before the island goes back to rest.
    public static let doneDuration: TimeInterval = 3.5
    /// A turn quicker than this says nothing about how long it took: "0:02" beside every quick reply is noise.
    public static let minTook: TimeInterval = 5

    /// How long the finished turn took, when it is worth saying: at least `minTook`, and Nod sent a usable span.
    public static func took(_ state: IslandState) -> TimeInterval? {
        guard case .done(_, let took) = state, let took, took.isFinite, took >= minTook else { return nil }
        return took
    }

    /// How long the last answer stays above the prompt, so a follow-up reads in context (as in Pippa).
    public static let followUpWindow: TimeInterval = 10 * 60
    /// An approval card that just appeared ignores Approve and Decline for this long, so a click meant for whatever
    /// was under the pointer cannot answer it.
    public static let answerGuard: TimeInterval = 0.8

    public static func acceptsAnswer(shownFor age: TimeInterval) -> Bool { age >= answerGuard }

    /// Return in the field. Words typed under Nod's question answer it (files go out as a new message), so while the
    /// question card has just (re)appeared Return waits out the same guard as a click on a choice: keys meant for
    /// another app must not answer Nod.
    /// Only uploaded files count here. A failed chip holds Return in the draft itself (`PromptDraft.submit`), so
    /// nothing answers while one is there.
    public static func acceptsTypedSubmit(question: Bool, draft: PromptDraft, shownFor age: TimeInterval) -> Bool {
        !question || !draft.ready.isEmpty || acceptsAnswer(shownFor: age)
    }

    /// How much longer the guard holds; 0 once the card takes answers. The buttons show dimmed until then.
    public static func answerGuardRemaining(shownFor age: TimeInterval) -> TimeInterval { max(0, answerGuard - age) }

    /// `doneAge`: seconds since the island first showed the current `.done`; nil if it has not shown it yet.
    /// `answerReady`: Nod answered while the card was closed and the person has not opened it since; "done" then stays
    /// until they look, like a message waiting to be read, also after the session has turned "done" back into rest.
    public static func tone(_ state: IslandState, doneAge: TimeInterval? = nil, answerReady: Bool = false) -> IslandTone {
        switch state {
        case .offline: .offline
        case .rest: answerReady ? .done : .rest
        case .working: .working
        case .needsYou, .asks: .needsYou
        case .done: !answerReady && (doneAge ?? 0) >= doneDuration ? .rest : .done
        case .failed: .failed
        }
    }

    /// The closed island's words for an answer nobody has read yet. Not the answer's first line: cut to the wing's
    /// width it reads as the whole answer.
    public static let answerReadyLine = "Answer ready"

    /// Nod answered while the card was closed: the person sent or followed this turn and is not looking at it.
    public static func answerArrived(from old: IslandState, to new: IslandState, open: Bool, answer: NodAnswer?) -> Bool {
        guard case .done = new, !open, answer != nil else { return false }
        if case .done = old { return false }
        return true
    }

    /// New work, an approval, a question or a failure takes over from an unread answer; a dropped connection does not.
    public static func endsAnswerReady(_ state: IslandState) -> Bool {
        [.working, .needsYou, .failed].contains(tone(state))
    }

    /// The UserDefaults key that remembers the login offer was shown and answered, either way.
    public static let loginOfferedKey = "nodch.loginOffered"

    /// Start at login is offered once, in the prompt: only while it is off, never offered before and Nod is reachable
    /// (so the first thing the person sees is nodch working, not a question). Nothing turns on without a click.
    public static func offersLogin(notRegistered: Bool, offeredBefore: Bool, connected: Bool) -> Bool {
        notRegistered && !offeredBefore && connected
    }

    /// What VoiceOver hears when the island changes by itself; nil when nothing new needs the person.
    /// `shortcut` is the display string of the global shortcut in effect (nil: none), so a person who cannot see the
    /// island hears how to reach the card that waits for them.
    public static func announcement(from old: IslandState, to new: IslandState, answerArrived: Bool, shortcut: String? = nil) -> String? {
        if answerArrived { return "Nod’s answer is ready" }
        // Without a shortcut the words stay as they were; with one, a sentence names it.
        func withWay(_ text: String) -> String {
            guard let shortcut = nonEmpty(shortcut) else { return text }
            return text + (".?!".contains(text.last ?? " ") ? "" : ".") + " Press \(shortcut) to open it."
        }
        if waitingID(new) != waitingID(old) {
            switch new {
            case .needsYou(let approval, _): return withWay("Nod needs you: " + (nonEmpty(approval.title) ?? "an approval"))
            case .asks: return withWay("Nod has a question")
            default: break
            }
        }
        if case .failed(let message) = new {
            if case .failed = old { return nil }
            return "Nod couldn’t finish: " + (nonEmpty(message) ?? "something went wrong")
        }
        return nil
    }

    /// What VoiceOver hears when a send or an upload fails: the card keeps the text and shows the reason, silently.
    public static func notSent(_ reason: String) -> String { "Not sent: " + (nonEmpty(reason) ?? "something went wrong") }

    /// The wing's line: the step and site while Nod works (the title when there is no step), the approval's title,
    /// the summary or the error.
    public static func line(_ state: IslandState, answerReady: Bool = false) -> String {
        if answerReady, tone(state, answerReady: true) == .done { return answerReadyLine }
        switch state {
        case .offline: return "Nod isn’t connected"
        case .rest: return ""
        case .working(let activity):
            let parts = [activity.step, activity.site].compactMap(nonEmpty)
            if !parts.isEmpty { return parts.joined(separator: " · ") }
            if let title = nonEmpty(activity.title) { return title }
            switch activity.doing {
            case .queued: return "Queued…"
            case .model: return "Thinking…"
            case .tool: return "Working…"
            }
        case .needsYou(let approval, _): return nonEmpty(approval.title) ?? "Nod needs you"
        case .asks(let answer): return nonEmpty(MarkdownPlain.line(answer.text)) ?? "Nod has a question"
        case .done(let summary, _): return nonEmpty(summary.map(MarkdownPlain.line)) ?? "Done"
        case .failed(let message): return nonEmpty(message) ?? "Something went wrong"
        }
    }

    /// The open working card's title and the live line under it. The header already says "Working" with a spinner, so
    /// without Nod's own title the live line becomes the title and nothing repeats; with a title the line under it is
    /// the step, or what Nod is doing, never the title again. The site has its own row.
    public static func workingCard(_ activity: WorkActivity) -> (title: String, step: String?) {
        let doing = switch activity.doing { case .queued: "Queued…"; case .model: "Thinking…"; case .tool: "Working…" }
        let step = nonEmpty(activity.step)
        guard let title = nonEmpty(activity.title) else { return (step ?? doing, nil) }
        return (title, step ?? doing)
    }

    /// The answer the prompt shows above its field: an open question always, otherwise a recent answer.
    /// `kept`: the id of an answer that arrived while the card was closed; it shows however late it is opened.
    public static func shownAnswer(_ answer: NodAnswer?, state: IslandState, now: Date = Date(), kept: String? = nil) -> NodAnswer? {
        if case .asks(let asked) = state { return asked }
        guard let answer, answer.id == kept || now.timeIntervalSince(answer.at) < followUpWindow else { return nil }
        return answer
    }

    /// What the person is asked to decide right now: an approval or Nod's question, by id.
    public static func waitingID(_ state: IslandState) -> String? {
        switch state {
        case .needsYou(let approval, _): "approval:" + approval.id
        case .asks(let answer): "question:" + answer.id
        default: nil
        }
    }

    /// Repeated updates for the same question must not take the keyboard again.
    public static func newQuestion(from old: IslandState, to new: IslandState) -> Bool {
        guard case .asks(let answer) = new else { return false }
        return waitingID(old) != "question:" + answer.id
    }

    /// Move a keyboard highlight without changing any selected answers.
    public static func nextChoice(_ current: String?, choices: [String], down: Bool) -> String? {
        guard !choices.isEmpty else { return nil }
        guard let current, let index = choices.firstIndex(of: current) else { return down ? choices.first : choices.last }
        return choices[min(max(index + (down ? 1 : -1), 0), choices.count - 1)]
    }

    /// The quiet key line under the prompt. `discards`: Escape would throw away words or files. ⌘↩ is named here,
    /// not in the Open Nod button beside the field: a wider button would narrow the field and wrap its placeholder.
    /// `answer`: an answer shows above the field; its copy key is named when no question's keys need the room.
    public static func promptHints(question: NodQuestion?, discards: Bool, answer: Bool = false) -> String {
        let tail = "  ·  " + (discards ? "esc discard" : "esc close") + "  ·  ⌘↩ open Nod"
        guard let question, !question.choices.isEmpty else { return "↩ send" + tail + (answer ? "  ·  ⇧⌘C copy" : "") }
        return (question.multiple ? "↑↓ navigate  ·  ↩ select  ·  ⌥↩ send" : "↑↓ navigate  ·  ↩ answer") + tail
    }

    /// Up and Down move between choices only while the field is empty; with words in it they belong to the field.
    public static func arrowsMoveChoices(field: String, choices: Int) -> Bool { field.isEmpty && choices > 0 }

    /// The short name of the state, for the card's header and VoiceOver.
    public static func heading(_ tone: IslandTone) -> String {
        switch tone {
        case .rest: "Ask Nod"
        case .offline: "Offline"
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    /// What the compact shape carries; nil leaves the island gone below the menu bar. `hovering`: the pointer is on
    /// the island. `notch`: at a camera housing the resting island keeps a small presence, the green "connected" dot
    /// beside the housing, so nodch is visibly there without ⌥Space; below a menu bar it stays out of the way.
    public static func wing(_ state: IslandState, tone: IslandTone, hovering: Bool, notch: Bool = true) -> IslandWing? {
        switch tone {
        case .rest:
            if hovering { return IslandWing(showsLine: false, showsHint: true) }
            return notch ? IslandWing(showsLine: false) : nil
        // Unobtrusive: just the sign; the words come on hover.
        case .offline: return IslandWing(showsLine: hovering)
        case .working: return IslandWing(showsElapsed: true, showsStop: true)
        case .needsYou:
            if case .needsYou(_, let more) = state { return IslandWing(more: max(0, more), showsChevron: more <= 0) }
            if case .asks = state { return IslandWing(showsChevron: true) }
            return IslandWing(showsChevron: true)
        case .done: return IslandWing(showsTook: took(state) != nil)
        case .failed: return IslandWing()
        }
    }

    /// Why the card opens. Only a person's own click, shortcut or drop gives it the keyboard; an approval that arrives
    /// while they type in another app shows without taking it. `dropTray`: files are dragged toward the closed island,
    /// so it grows into one large target and folds away again when they leave or land elsewhere.
    public enum OpenCause: Equatable, Sendable { case click, hotkey, drop, approval, dropTray }

    /// The drag belongs to another app until the files land: the tray never takes the keyboard from it.
    public static func takesKey(_ cause: OpenCause) -> Bool { cause != .approval && cause != .dropTray }

    /// The shortcut brings the prompt, except while Nod is not connected: then it brings the card that says why,
    /// with Settings and Retry, and the microphone stays off.
    public static func hotkeyOpensPrompt(_ tone: IslandTone) -> Bool { tone != .offline }

    /// A click on the island brings the prompt at rest, right after an answer, on Nod's question and after a failed
    /// turn (the reason stays in the line above the field, so the person can try again). Working, an approval and
    /// offline open the card that fits them.
    public static func clickOpensPrompt(_ tone: IslandTone, asking: Bool) -> Bool {
        asking || tone == .rest || tone == .done || tone == .failed
    }

    /// A card the person opened closes on a click elsewhere. One that opened by itself for an approval stays until it
    /// is answered or collapsed: a click in another app is not a decision about it.
    public static func closesOnOutsideClick(_ cause: OpenCause) -> Bool { cause != .approval }

    /// What the shortcut does to the card.
    public enum HotkeyAction: Equatable, Sendable {
        /// The quick prompt opens.
        case open
        /// The open card turns into the prompt and takes the keyboard.
        case prompt
        /// The prompt hides and the keyboard goes back. Its words and files stay for next time; only Escape discards.
        case hide
        /// An approval card that opened by itself takes the keyboard, so its keys work. The next press brings the
        /// prompt, and the approval waits in the wing while the person types.
        case takeKey
    }

    /// `open`: the card is open; `prompt`: it shows the prompt; `key`: it has the keyboard; `approvalCard`: it shows
    /// an approval; `offline`: Nod is not connected.
    public static func hotkey(open: Bool, prompt: Bool, key: Bool, approvalCard: Bool, offline: Bool = false) -> HotkeyAction {
        guard open else { return .open }
        if prompt { return key ? .hide : .prompt }
        // Offline the card says why and offers Settings and Retry; a prompt could not be sent.
        if offline { return key ? .hide : .takeKey }
        return approvalCard && !key ? .takeKey : .prompt
    }

    /// A key the open card answers to while a modifier is held. Plain keys stay with the field and the choice list.
    public enum CardKey: Equatable, Sendable { case returnKey, delete, period, c }
    public enum KeyModifier: Equatable, Sendable { case none, command, option, commandShift }

    /// What the card on screen offers to the keyboard.
    public struct CardOffers: Equatable, Sendable {
        /// The approval card with Approve and Decline.
        public var approval: Bool
        /// A Stop button for the running turn.
        public var stop: Bool
        /// Ticked choices on a multiple-choice question, and an empty field: they can go out as they are.
        public var picks: Bool
        /// Nod's answer shows above the prompt: it can be copied whole.
        public var answer: Bool

        public init(approval: Bool = false, stop: Bool = false, picks: Bool = false, answer: Bool = false) {
            self.approval = approval; self.stop = stop; self.picks = picks; self.answer = answer
        }
    }

    public enum KeyAction: Equatable, Sendable { case approve, decline, stop, sendPicks, openNod, copyAnswer }

    /// ⌘Return does what "Open Nod" does, on every card. ⌥Return approves and ⌥⌫ declines on the approval card; ⌥Return sends ticked choices (like their Send button);
    /// ⌘. stops a running turn; ⇧⌘C copies the answer on show (⌘C stays with the selection). Plain Return never
    /// approves and keeps ticking choices.
    /// The app asks only while the island has the keyboard, and Approve and Decline still wait out `answerGuard`.
    public static func keyAction(_ key: CardKey, _ modifier: KeyModifier, offers: CardOffers) -> KeyAction? {
        switch (key, modifier) {
        case (.returnKey, .command): .openNod
        case (.returnKey, .option): offers.approval ? .approve : offers.picks ? .sendPicks : nil
        case (.delete, .option): offers.approval ? .decline : nil
        case (.period, .command): offers.stop ? .stop : nil
        case (.c, .commandShift): offers.answer ? .copyAnswer : nil
        default: nil
        }
    }

    /// Under the prompt for a moment after ⇧⌘C or "Copy answer", and what VoiceOver hears.
    public static let answerCopied = "Answer copied"

    /// The approval card's quiet key line.
    public static let approvalHints = "⌥↩ approve  ·  ⌥⌫ decline  ·  esc close"

    public enum Reaction: Equatable, Sendable { case none, reveal, conceal }

    /// What a change of state does to the card. `open`: why the card is open now, nil when it is closed.
    /// - A new approval (or another one) reveals the card, without the keyboard, unless the person has it open already.
    ///   The drop tray is not a card the person reads: an approval takes its place.
    /// - When the approval it opened for is gone, a card that opened by itself closes again.
    /// - A card left on a state that has nothing to show (rest) closes; one that shows an answer stays for reading.
    public static func reaction(from old: IslandState, to new: IslandState, open: OpenCause?) -> Reaction {
        let oldID = waitingID(old)
        if let newID = waitingID(new) {
            guard newID != oldID else { return .none }
            return open == nil || open == .dropTray ? .reveal : .none
        }
        if oldID != nil, open == .approval { return .conceal }
        if case .done = old { return .none }
        if case .rest = new, open == .click, tone(old) != .rest { return .conceal }
        return .none
    }

    /// "0:07", "12:05", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
