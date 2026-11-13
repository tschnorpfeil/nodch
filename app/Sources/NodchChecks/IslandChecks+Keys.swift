import Foundation
import NodchCore

extension IslandChecks {
    /// The keyboard paths through the cards and the hints that name them.
    static func keys() {
        typealias P = IslandPresentation

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
