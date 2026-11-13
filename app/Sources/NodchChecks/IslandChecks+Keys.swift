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
    }
}
