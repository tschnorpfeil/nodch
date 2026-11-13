import Foundation
import NodchCore

extension IslandChecks {
    static func answers() {
        typealias P = IslandPresentation
        let now = Date()
        let question = NodQuestion(choices: [.init(id: "c1", label: "Tomorrow"), .init(id: "c2", label: "Later")], multiple: false)
        let asked = NodAnswer(id: "q1", text: "**When** should I book it?", at: now.addingTimeInterval(-3600), question: question)
        let asks = IslandState.asks(asked)

        // The wing is one line of plain text: no Markdown marks.
        check(P.line(.done(summary: "**Morgen** ist *Samstag*.\n\n- `a`")) == "Morgen ist Samstag. a", "answers: the done line drops Markdown")
        check(P.line(asks) == "When should I book it?", "answers: Nod's question reads as plain text in the wing")
        check(P.tone(asks) == .needsYou && P.wing(asks, tone: .needsYou, hovering: false)?.showsChevron == true,
              "answers: a question waits for the person like an approval")

        // A question opens the card by itself, without the keyboard, and closes it once answered.
        check(P.reaction(from: .rest, to: asks, open: nil) == .reveal, "answers: Nod's question reveals the card")
        check(P.reaction(from: asks, to: asks, open: nil) == .none, "answers: the same question does not reopen a collapsed card")
        check(P.reaction(from: asks, to: .working(WorkActivity(title: nil, step: nil, site: nil, since: now, doing: .model)), open: .approval) == .conceal,
              "answers: an answered question closes the card it opened")
        check(P.reaction(from: .needsYou(approval("q1"), more: 0), to: asks, open: nil) == .reveal,
              "answers: an approval and a question with the same id are different things to decide")

        // Above the prompt: the open question always, the last answer for ten minutes.
        let recent = NodAnswer(id: "m1", text: "Done.", at: now.addingTimeInterval(-60))
        let old = NodAnswer(id: "m0", text: "Done.", at: now.addingTimeInterval(-P.followUpWindow - 1))
        check(P.shownAnswer(recent, state: .rest, now: now) == recent, "answers: a recent answer stays above the prompt")
        check(P.shownAnswer(old, state: .rest, now: now) == nil, "answers: an old answer leaves the prompt empty")
        check(P.shownAnswer(nil, state: asks, now: now) == asked, "answers: an open question shows however old it is")

        // A click on a choice goes out like a send (review S1–S3).
        var draft = PromptDraft(text: "und bitte vormittags")
        check(draft.answerChoice() == [] && draft.sending, "answers: a choice click locks the draft like a send")
        check(draft.submit().isEmpty && draft.answerChoice() == nil, "answers: Return or a second click sends nothing while a choice is out")
        let token = draft.sendToken
        draft.answeredKeepingText(token: token)
        check(!draft.sending && draft.text == "und bitte vormittags", "answers: a choice without the words gives the field back with them")
        _ = draft.answerChoice()
        draft.sendFailed("Nod rejected it", token: draft.sendToken)
        check(draft.error == "Nod rejected it" && !draft.sending, "answers: a rejected choice says why under the field")
        _ = draft.answerChoice()
        let earlier = draft.sendToken
        _ = draft.escape()
        _ = draft.typed("neue Frage")
        check(!draft.sent(token: earlier) && draft.display == "neue Frage", "answers: a late answer never clears a newer draft")
        var listening = PromptDraft()
        _ = listening.open(.hotkey)
        listening.voiceStarted()
        listening.heard("morgen", final: false)
        check(listening.answerChoice() == [.stopVoice(finalize: false)] && listening.voice == .off && listening.text == "morgen",
              "answers: a choice turns the microphone off and keeps its words")

        // The mapper turns an open question into `.asks` once no turn runs.
        let id = "00000000-0000-4000-8000-0000000000"
        let json = """
        {"threadId":"\(id)01","messages":[{"id":"\(id)12","role":"assistant","text":"When?","turnId":"\(id)a2","createdAt":"2026-11-13T08:02:00.000Z","answerChoices":{"options":[{"id":"\(id)c1","label":"Now"}],"multiple":false},"answerChoicesPending":true}],"turns":[{"id":"\(id)a2","status":"waiting","source":"user","createdAt":"2026-11-13T08:00:00.000Z","finishedAt":null,"error":null}],"activity":[]}
        """
        var mapper = NodStateMapper()
        if let state = try? NodState.decode(Data(json.utf8)), case .asks(let answer) = mapper.map(state) {
            check(answer.id == "\(id)12" && answer.question?.choices.map(\.label) == ["Now"], "answers: an open question maps to asks")
        } else {
            check(false, "answers: an open question maps to asks")
        }
    }
}
