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

    public init(showsGlyph: Bool = true, showsLine: Bool = true, showsElapsed: Bool = false, showsStop: Bool = false,
                showsHint: Bool = false, more: Int = 0, showsChevron: Bool = false) {
        self.showsGlyph = showsGlyph; self.showsLine = showsLine; self.showsElapsed = showsElapsed; self.showsStop = showsStop
        self.showsHint = showsHint; self.more = more; self.showsChevron = showsChevron
    }
}

public enum IslandPresentation {
    /// How long "done" shows before the island goes back to rest.
    public static let doneDuration: TimeInterval = 3.5
    /// How long the last answer stays above the prompt, so a follow-up reads in context (as in Pippa).
    public static let followUpWindow: TimeInterval = 10 * 60
    /// An approval card that just appeared ignores Approve and Decline for this long, so a click meant for whatever
    /// was under the pointer cannot answer it.
    public static let answerGuard: TimeInterval = 0.8

    public static func acceptsAnswer(shownFor age: TimeInterval) -> Bool { age >= answerGuard }

    /// `doneAge`: seconds since the island first showed the current `.done`; nil if it has not shown it yet.
    public static func tone(_ state: IslandState, doneAge: TimeInterval? = nil) -> IslandTone {
        switch state {
        case .offline: .offline
        case .rest: .rest
        case .working: .working
        case .needsYou, .asks: .needsYou
        case .done: (doneAge ?? 0) >= doneDuration ? .rest : .done
        case .failed: .failed
        }
    }

    /// The wing's line: the step and site while Nod works (the title when there is no step), the approval's title,
    /// the summary or the error.
    public static func line(_ state: IslandState) -> String {
        switch state {
        case .offline: return "Nod is offline"
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
        case .done(let summary): return nonEmpty(summary.map(MarkdownPlain.line)) ?? "Done"
        case .failed(let message): return nonEmpty(message) ?? "Something went wrong"
        }
    }

    /// The answer the prompt shows above its field: an open question always, otherwise a recent answer.
    public static func shownAnswer(_ answer: NodAnswer?, state: IslandState, now: Date = Date()) -> NodAnswer? {
        if case .asks(let asked) = state { return asked }
        guard let answer, now.timeIntervalSince(answer.at) < followUpWindow else { return nil }
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

    /// The quiet key line under the prompt. `discards`: Escape would throw away words or files.
    public static func promptHints(question: NodQuestion?, discards: Bool) -> String {
        let escape = discards ? "esc discard" : "esc close"
        guard let question, !question.choices.isEmpty else { return "↩ send  ·  " + escape }
        return (question.multiple ? "↑↓ navigate  ·  ↩ select  ·  Send to answer" : "↑↓ navigate  ·  ↩ answer") + "  ·  " + escape
    }

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

    /// What the compact shape carries; nil leaves the island at rest inside the housing (or gone below the menu bar).
    /// `hovering`: the pointer is on the island.
    public static func wing(_ state: IslandState, tone: IslandTone, hovering: Bool) -> IslandWing? {
        switch tone {
        case .rest: return hovering ? IslandWing(showsLine: false, showsHint: true) : nil
        // Unobtrusive: just the sign; the words come on hover.
        case .offline: return IslandWing(showsLine: hovering)
        case .working: return IslandWing(showsElapsed: true, showsStop: true)
        case .needsYou:
            if case .needsYou(_, let more) = state { return IslandWing(more: max(0, more), showsChevron: more <= 0) }
            if case .asks = state { return IslandWing(showsChevron: true) }
            return IslandWing(showsChevron: true)
        case .done, .failed: return IslandWing()
        }
    }

    /// Why the card opens. Only a person's own click, shortcut or drop gives it the keyboard; an approval that arrives
    /// while they type in another app shows without taking it.
    public enum OpenCause: Equatable, Sendable { case click, hotkey, drop, approval }

    public static func takesKey(_ cause: OpenCause) -> Bool { cause != .approval }

    /// A card the person opened closes on a click elsewhere. One that opened by itself for an approval stays until it
    /// is answered or collapsed: a click in another app is not a decision about it.
    public static func closesOnOutsideClick(_ cause: OpenCause) -> Bool { cause != .approval }

    public enum Reaction: Equatable, Sendable { case none, reveal, conceal }

    /// What a change of state does to the card. `open`: why the card is open now, nil when it is closed.
    /// - A new approval (or another one) reveals the card, without the keyboard, unless the person has it open already.
    /// - When the approval it opened for is gone, a card that opened by itself closes again.
    /// - A card left on a state that has nothing to show (rest) closes; one that shows an answer stays for reading.
    public static func reaction(from old: IslandState, to new: IslandState, open: OpenCause?) -> Reaction {
        let oldID = waitingID(old)
        if let newID = waitingID(new) {
            guard newID != oldID else { return .none }
            return open == nil ? .reveal : .none
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
