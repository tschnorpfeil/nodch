import Foundation
import NodchCore

extension IslandChecks {
    /// The keyboard paths through the cards and the hints that name them.
    static func keys() {
        typealias P = IslandPresentation

        // The shortcut on the open prompt hides it; the draft is there on the next open, the microphone off meanwhile.
        check(P.hotkey(open: true, prompt: true, key: true, approvalCard: false) == .hide, "keys: the shortcut on the open prompt hides it")
        check(P.hotkey(open: false, prompt: true, key: false, approvalCard: false) == .open
              && P.hotkey(open: true, prompt: true, key: false, approvalCard: false) == .prompt
              && P.hotkey(open: true, prompt: false, key: true, approvalCard: false) == .prompt, "keys: otherwise the shortcut brings the prompt")
        var kept = PromptDraft()
        _ = kept.open(.hotkey)
        kept.voiceStarted()
        kept.heard("Summarize my mail", final: true)
        kept.heard("from today", final: false)
        _ = kept.drop([DroppedFile(url: URL(fileURLWithPath: "/tmp/drop/q4.pdf"), isDirectory: false)])
        check(kept.closed() == [.stopVoice(finalize: false)] && kept.voice == .off, "keys: hiding turns the microphone off")
        _ = kept.open(.click)
        check(kept.display == "Summarize my mail from today" && kept.attachments.count == 1,
              "keys: the hidden draft keeps its words and files for the next open")

        // The approval card: ⌥Return approves, ⌥⌫ declines, never plain Return; ⌘. stops a running turn.
        let approvalCard = P.CardOffers(approval: true)
        check(P.keyAction(.returnKey, .option, offers: approvalCard) == .approve, "keys: ⌥Return approves on the approval card")
        check(P.keyAction(.delete, .option, offers: approvalCard) == .decline, "keys: ⌥⌫ declines on the approval card")
        check(P.keyAction(.returnKey, .none, offers: approvalCard) == nil, "keys: plain Return never approves")
        check(P.keyAction(.returnKey, .option, offers: .init()) == nil && P.keyAction(.delete, .option, offers: .init()) == nil,
              "keys: ⌥Return and ⌥⌫ belong to the field when no approval card shows")
        check(P.keyAction(.period, .command, offers: .init(stop: true)) == .stop && P.keyAction(.period, .command, offers: .init()) == nil,
              "keys: ⌘. stops only where a Stop button shows")
        check(P.hotkey(open: true, prompt: false, key: false, approvalCard: true) == .takeKey,
              "keys: the shortcut gives an approval card that opened by itself the keyboard")
        check(P.hotkey(open: true, prompt: false, key: true, approvalCard: true) == .prompt,
              "keys: pressed again, the shortcut brings the prompt and the approval waits in the wing")

        // A multiple-choice question: Return ticks, ⌥Return sends the ticks while the field is empty.
        check(P.keyAction(.returnKey, .option, offers: .init(picks: true)) == .sendPicks, "keys: ⌥Return sends the ticked choices")
        check(P.keyAction(.returnKey, .option, offers: .init(picks: false)) == nil, "keys: ⌥Return without ticks (or with words) stays in the field")
        check(P.keyAction(.returnKey, .none, offers: .init(picks: true)) == nil, "keys: plain Return keeps ticking choices")
        let several = NodQuestion(choices: [.init(id: "p1", label: "Newsletter")], multiple: true)
        check(P.promptHints(question: several, discards: false) == "↑↓ navigate  ·  ↩ select  ·  ⌥↩ send  ·  esc close",
              "keys: a multiple-choice question names ⌥↩ send")

        // Escape discards a draft with something in it; the hint must say so.
        var empty = PromptDraft()
        check(!empty.discardsOnEscape && P.promptHints(question: nil, discards: false) == "↩ send  ·  esc close",
              "keys: an empty prompt says esc close")
        _ = empty.typed("Hello")
        check(empty.discardsOnEscape && P.promptHints(question: nil, discards: true) == "↩ send  ·  esc discard",
              "keys: a prompt with words says esc discard")
        var files = PromptDraft()
        _ = files.drop([DroppedFile(url: URL(fileURLWithPath: "/tmp/drop/a.pdf"), isDirectory: false)])
        check(files.discardsOnEscape, "keys: a prompt with only files also discards on Escape")
        let single = NodQuestion(choices: [.init(id: "c1", label: "Now")], multiple: false)
        check(P.promptHints(question: single, discards: true).hasSuffix("esc discard")
              && P.promptHints(question: single, discards: false).hasSuffix("esc close"), "keys: question hints name what Escape does")

        // Up and Down belong to the field once it has words.
        check(P.arrowsMoveChoices(field: "", choices: 3), "keys: arrows move between choices while the field is empty")
        check(!P.arrowsMoveChoices(field: "und vormittags", choices: 3), "keys: arrows stay in a field with words")
        check(!P.arrowsMoveChoices(field: "", choices: 0), "keys: arrows without choices stay in the field")

        // A question takes the keyboard only on a card the person opened.
        check(P.questionTakesKey(open: .hotkey) && P.questionTakesKey(open: .click) && P.questionTakesKey(open: .drop),
              "keys: a question on a card the person opened takes the keyboard")
        check(!P.questionTakesKey(open: .approval), "keys: a question on a card that opened by itself leaves the keyboard alone")
        check(!P.questionTakesKey(open: nil), "keys: a question on a closed card leaves the keyboard alone")

        // The click guard's state, for the dimmed buttons: on while answers are refused, off exactly when they count.
        check(P.answerGuardRemaining(shownFor: 0) == P.answerGuard && P.answerGuardRemaining(shownFor: 0.3) > 0
              && !P.acceptsAnswer(shownFor: 0.3), "keys: the guard holds, and says so, right after a card appears")
        check(P.answerGuardRemaining(shownFor: P.answerGuard) == 0 && P.acceptsAnswer(shownFor: P.answerGuard)
              && P.answerGuardRemaining(shownFor: 60) == 0, "keys: the guard ends exactly when answers count")
    }
}
