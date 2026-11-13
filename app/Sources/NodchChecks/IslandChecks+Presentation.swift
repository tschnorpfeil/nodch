import Foundation
import NodchCore

extension IslandChecks {
    static func approval(_ id: String, title: String = "Send this email?") -> PendingApproval {
        PendingApproval(id: id, messageID: "m-\(id)", title: title, app: "Gmail", fields: [], body: "Hi", bodyCut: false)
    }

    static func presentation() {
        let since = Date().addingTimeInterval(-30)
        let working = IslandState.working(WorkActivity(title: "Expense report", step: "Reading invoices", site: "mail.google.com", since: since, doing: .tool))
        let a = IslandState.needsYou(approval("a"), more: 0)
        let b = IslandState.needsYou(approval("b"), more: 2)
        typealias P = IslandPresentation

        // Focus: only the person's own action takes the keyboard.
        check(!P.takesKey(.approval), "presentation: an approval never takes key focus")
        check(P.takesKey(.hotkey) && P.takesKey(.click), "presentation: the shortcut and a click take key focus")
        check(!P.closesOnOutsideClick(.approval) && P.closesOnOutsideClick(.click) && P.closesOnOutsideClick(.hotkey),
              "presentation: a card opened for an approval survives clicks in other apps")

        // What a change of state does.
        check(P.reaction(from: working, to: a, open: nil) == .reveal, "presentation: a new approval reveals the card")
        check(P.reaction(from: a, to: a, open: nil) == .none, "presentation: the same approval does not reopen a collapsed card")
        check(P.reaction(from: a, to: b, open: nil) == .reveal, "presentation: the next approval reveals the card again")
        check(P.reaction(from: working, to: a, open: .hotkey) == .none, "presentation: an approval does not take over the open prompt")
        check(P.reaction(from: a, to: working, open: .approval) == .conceal, "presentation: an answered approval closes the card it opened")
        check(P.reaction(from: a, to: working, open: .click) == .none, "presentation: a card the person opened stays")
        check(P.reaction(from: .done(summary: nil), to: .rest, open: .click) == .conceal, "presentation: a status card closes at rest")
        check(P.reaction(from: .rest, to: .rest, open: .hotkey) == .none, "presentation: the prompt stays open at rest")

        // Done returns to rest.
        check(P.tone(.done(summary: "Sent")) == .done, "presentation: done shows first")
        check(P.tone(.done(summary: "Sent"), doneAge: P.doneDuration - 0.1) == .done, "presentation: done holds briefly")
        check(P.tone(.done(summary: "Sent"), doneAge: P.doneDuration) == .rest, "presentation: done returns to rest")
        check(P.doneDuration >= 2 && P.doneDuration <= 5, "presentation: done shows for 2–5 s")

        // Wings.
        check(P.wing(.rest, tone: .rest, hovering: false) == nil, "presentation: rest is just the notch")
        check(P.wing(.rest, tone: .rest, hovering: true)?.showsHint == true, "presentation: hovering the resting notch reveals the shortcut")
        let offline = IslandState.offline(reason: "x")
        check(P.wing(offline, tone: .offline, hovering: false)?.showsLine == false && P.wing(offline, tone: .offline, hovering: true)?.showsLine == true,
              "presentation: offline is a quiet sign that explains itself on hover")
        let workWing = P.wing(working, tone: .working, hovering: false)
        check(workWing?.showsElapsed == true && workWing?.showsStop == true, "presentation: working shows elapsed time and Stop")
        check(P.wing(b, tone: .needsYou, hovering: false)?.more == 2 && P.wing(a, tone: .needsYou, hovering: false)?.more == 0,
              "presentation: needs you counts further approvals")

        // Lines.
        check(P.line(working) == "Reading invoices · mail.google.com", "presentation: the wing names step and site")
        check(P.line(.working(WorkActivity(title: "Expense report", step: nil, site: nil, since: since, doing: .model))) == "Expense report",
              "presentation: without a step the wing names the title")
        check(P.line(.working(WorkActivity(title: " ", step: nil, site: nil, since: since, doing: .queued))) == "Queued…",
              "presentation: without words the wing says what Nod does")
        check(P.line(.needsYou(approval("c", title: ""), more: 0)) == "Nod needs you", "presentation: an untitled approval still reads")
        check(P.line(.done(summary: nil)) == "Done" && P.line(.failed(message: "Boom")) == "Boom", "presentation: done and failed lines")

        // Elapsed time.
        check(P.elapsed(7) == "0:07" && P.elapsed(725) == "12:05" && P.elapsed(3723) == "1:02:03" && P.elapsed(-3) == "0:00",
              "presentation: elapsed time reads m:ss and h:mm:ss")
    }
}
