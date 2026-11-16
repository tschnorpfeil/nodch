import Foundation
import NodchCore

extension IslandChecks {
    /// An answer that arrives while the card is closed waits, as "Answer ready", until the person opens it.
    static func answerReady() {
        typealias P = IslandPresentation
        let now = Date()
        let answer = NodAnswer(id: "m1", text: "**Morgen** ist Samstag.", at: now.addingTimeInterval(-3600))
        let working = IslandState.working(WorkActivity(title: "Kalender", step: nil, site: nil, since: now, doing: .model))
        let done = IslandState.done(summary: "Morgen ist Samstag, der 14. November. Ich sehe deinen Kalender.")

        check(P.answerArrived(from: working, to: done, open: false, answer: answer)
              && !P.answerArrived(from: working, to: done, open: true, answer: answer)
              && !P.answerArrived(from: done, to: done, open: false, answer: answer)
              && !P.answerArrived(from: working, to: done, open: false, answer: nil),
              "ready: only a new answer to a closed card waits to be read")
        check(P.tone(done, doneAge: .infinity, answerReady: true) == .done && P.tone(.rest, answerReady: true) == .done
              && P.tone(done, doneAge: .infinity) == .rest && P.tone(.rest) == .rest,
              "ready: it stays after done would fade, also once the session turned it into rest")
        check(P.line(done, answerReady: true) == "Answer ready" && P.line(.rest, answerReady: true) == "Answer ready"
              && P.line(working, answerReady: true) != "Answer ready",
              "ready: the closed island says Answer ready, not a cut first line")
        check(P.endsAnswerReady(working) && P.endsAnswerReady(.failed(message: "x"))
              && !P.endsAnswerReady(.offline(reason: "Event stream disconnected.")) && !P.endsAnswerReady(.rest),
              "ready: a dropped connection keeps the unread answer; new work ends it")
        check(P.shownAnswer(answer, state: .rest, now: now, kept: "m1") == answer && P.shownAnswer(answer, state: .rest, now: now) == nil,
              "ready: the kept answer shows however late the card opens")
        check(P.announcement(from: working, to: done, answerArrived: true) == "Nod’s answer is ready"
              && P.announcement(from: working, to: .failed(message: "Timed out"), answerArrived: false) == "Nod couldn’t finish: Timed out"
              && P.announcement(from: .rest, to: working, answerArrived: false) == nil,
              "ready: VoiceOver hears an answer, a failure, an approval or a question, nothing else")
        let waiting = IslandState.needsYou(approval("w", title: "Send this email?"), more: 0)
        let question = IslandState.asks(NodAnswer(id: "q9", text: "When?", at: now))
        check(P.announcement(from: working, to: waiting, answerArrived: false, shortcut: "⌥Space") == "Nod needs you: Send this email? Press ⌥Space to open it."
              && P.announcement(from: working, to: question, answerArrived: false, shortcut: "⌥Space") == "Nod has a question. Press ⌥Space to open it."
              && P.announcement(from: working, to: waiting, answerArrived: false, shortcut: nil) == "Nod needs you: Send this email?"
              && P.announcement(from: working, to: question, answerArrived: false, shortcut: " ") == "Nod has a question",
              "announcements: an approval or question names the shortcut that opens it; no shortcut, no suffix")
        check(P.notSent("Nothing answers at http://localhost:4310.") == "Not sent: Nothing answers at http://localhost:4310."
              && P.notSent(" ") == "Not sent: something went wrong",
              "announcements: a failed send or upload says Not sent and why")
    }
}
