import Foundation
import NodchCore

extension IslandChecks {
    /// What the notch says and does when work moves to Nod: the drop tray's destination, a shortened approval, and
    /// where "Open Nod" goes for the card on show.
    static func handoff() {
        typealias P = IslandPresentation
        let local = URL(string: "http://localhost:4310")!, remote = URL(string: "https://nod.example.com")!
        let v6 = URL(string: "http://[::1]:4310")!, lan = URL(string: "http://192.168.1.20:4310")!
        let offline = IslandState.offline(reason: "localhost:4310")

        // Drop tray: the session's host and port, local or remote, before anything is released.
        let onMac = P.dropDestination(server: local)
        check(onMac.place == .thisMac && onMac.address == "localhost:4310" && onMac.destination == "Nod on this Mac · localhost:4310"
              && onMac.uploads && onMac.note.contains("upload on drop") && onMac.note.contains("Press Return to send the prompt"),
              "drop tray: a Nod on this Mac shows host and port, keeps the upload timing and says nothing is sent yet")
        let away = P.dropDestination(server: remote)
        check(away.place == .remote && away.address == "nod.example.com:443" && away.destination == "Remote Nod · nod.example.com:443"
              && away.uploads, "drop tray: a remote Nod says so, with the scheme's default port spelled out")
        check(P.dropDestination(server: v6).address == "[::1]:4310"
              && P.dropDestination(server: v6).place == .thisMac
              && P.dropDestination(server: lan).place == .remote
              && P.dropDestination(server: URL(string: "http://nod.example.com")!).address == "nod.example.com:80",
              "drop tray: IPv6 loopback is on this Mac, a LAN address is remote, http defaults to port 80")
        let secret = URL(string: "https://user:hunter2@nod.example.com:8443/path?token=abc#frag")!
        let shown = P.dropDestination(server: secret)
        check(shown.address == "nod.example.com:8443"
              && ![shown.destination, shown.note, shown.spoken].compactMap { $0 }.contains { $0.contains("hunter2") || $0.contains("token") || $0.contains("path") },
              "drop tray: only host and port show, never a credential or path")
        let none = P.dropDestination(server: nil)
        check(none.place == nil && none.address == nil && none.destination == nil && !none.uploads
              && none.note.contains("Settings"),
              "drop tray: without a configured session it names the next step and does not invite a drop")
        check(onMac.spoken.contains("localhost, port 4310") && away.spoken.contains("Remote Nod at nod.example.com, port 443")
              && P.dropDestination(server: v6).spoken.contains("[::1], port 4310"),
              "drop tray: VoiceOver hears the place, host and port")

        // The session captures its address at creation, carries no credential, and the connection clears it.
        let store = IslandStore()
        check(store.server == nil, "drop tray: a store without a session has no address")
        let session = NodSession(client: NodClient(configuration: NodConfiguration(baseURL: remote, credential: .bearer("sekret-token"))), store: store)
        check(store.server == remote && store.server?.absoluteString.contains("sekret") == false && store.actions === session,
              "drop tray: the session that uploads is the source of the address, token stays out of it")
        session.disconnect()

        // A shortened approval: no Approve anywhere (button, ⌥Return), Decline and ⌘Return stay.
        let full = approval(cut: false), cut = approval(cut: true)
        check(full.approvableHere && !cut.approvableHere, "approval: only a full approval can be approved here")
        let fullOffers = P.CardOffers(approval: true, approvable: full.approvableHere)
        let cutOffers = P.CardOffers(approval: true, approvable: cut.approvableHere)
        check(P.keyAction(.returnKey, .option, offers: fullOffers) == .approve && P.keyAction(.returnKey, .option, offers: cutOffers) == nil,
              "approval: ⌥Return approves a full approval and does nothing on a shortened one")
        check(P.keyAction(.delete, .option, offers: cutOffers) == .decline && P.keyAction(.returnKey, .command, offers: cutOffers) == .openNod
              && P.keyAction(.returnKey, .none, offers: cutOffers) == nil,
              "approval: a shortened approval still declines with ⌥⌫, reviews with ⌘Return and never approves with Return")
        check(P.keyAction(.returnKey, .option, offers: .init(approval: true)) == .approve
              && P.keyAction(.returnKey, .option, offers: .init(approval: false, approvable: false, picks: true)) == .sendPicks,
              "approval: the default offers keep approving, and picks are untouched")
        check(P.approvalHints(approvable: true).contains("⌥↩ approve") && !P.approvalHints(approvable: false).contains("approve")
              && P.approvalHints(approvable: false).contains("⌘↩ review in Nod") && P.approvalHints(approvable: false).contains("⌥⌫ decline")
              && P.approvalHints(approvable: false).contains("esc close"),
              "approval: the key line names review, not approve, for a shortened approval")
        check(P.shortenedNotice.contains("Review") && !P.shortenedNotice.contains("Open Nod") && P.reviewInNod == "Review in Nod",
              "approval: one Review in Nod action, no second Open Nod wording")

        // Where "Open Nod" and ⌘Return go for the card on show.
        let activity = { (task: String?) in IslandState.working(WorkActivity(title: nil, step: nil, site: nil, since: Date(), doing: .tool, taskID: task)) }
        let answer = NodAnswer(id: "a1", text: "Done", at: Date())
        let page = { (state: IslandState, prompt: Bool, shown: Bool) in P.openPage(state, prompt: prompt, answerShown: shown) }
        check(page(.needsYou(cut, more: 0), false, false) == .chat && page(.needsYou(full, more: 0), true, false) == .chat,
              "open: a pending approval opens the main chat, also while the prompt is up")
        check(page(.asks(answer), false, true) == .chat && page(.asks(answer), true, true) == .chat
              && page(.done(summary: "x"), true, true) == .chat && page(.rest, true, true) == .chat && page(.done(summary: nil), false, false) == .chat,
              "open: a question, a result and a follow-up open the main chat")
        check(page(activity("00000000-0000-4000-8000-00000000d0c1"), false, false) == .tasks && page(activity(nil), false, false) == .chat,
              "open: a working card with a task id opens Scheduled tasks, unnamed work the main chat")
        check(page(activity("00000000-0000-4000-8000-00000000d0c1"), true, false) == nil,
              "open: the prompt over a task shows no task, so it opens Nod as Settings says")
        check(page(.rest, true, false) == nil && page(offline, false, false) == nil && page(.failed(message: "x"), false, false) == nil
              && page(.rest, false, false) == nil, "open: an empty prompt, offline and a failure open Nod as Settings says")
        check(P.NodPage.chat.path == "/" && P.NodPage.tasks.path == "/tasks", "open: only pages Nod has")

        // The browser plan stays on the configured origin; a plain open keeps the Settings choice.
        let tailnet = NodConfiguration(baseURL: URL(string: "https://mac.example.ts.net:4310")!, credential: .bearer("sekret-token"))
        let here = NodConfiguration(baseURL: local, credential: .none)
        let contextual = OpenTarget.automatic.plan(path: "/tasks", configuration: here, appInstalled: true)
        check(contextual == .browser(URL(string: "http://localhost:4310/tasks")!)
              && OpenTarget.app.plan(path: "/", configuration: here, appInstalled: true) == .browser(URL(string: "http://localhost:4310/")!),
              "open plan: a card's page opens in the browser at the configured server even when the app is preferred or installed")
        check(OpenTarget.automatic.plan(path: nil, configuration: here, appInstalled: true) == .app(fallback: URL(string: "http://localhost:4310/")!)
              && OpenTarget.automatic.plan(path: nil, configuration: tailnet, appInstalled: true) == .browser(URL(string: "https://mac.example.ts.net:4310/")!)
              && OpenTarget.app.plan(path: nil, configuration: tailnet, appInstalled: true) == .app(fallback: URL(string: "https://mac.example.ts.net:4310/")!)
              && OpenTarget.browser.plan(path: nil, configuration: here, appInstalled: true) == .browser(URL(string: "http://localhost:4310/")!)
              && OpenTarget.automatic.plan(path: nil, configuration: here, appInstalled: false) == .browser(URL(string: "http://localhost:4310/")!),
              "open plan: a plain Open Nod keeps the Settings choice, with the browser address as the fallback")
        let tasks = OpenTarget.browser.plan(path: "/tasks", configuration: tailnet, appInstalled: false)
        let escape = OpenTarget.browser.plan(path: "https://evil.example/tasks", configuration: tailnet, appInstalled: false)
        if case .browser(let url) = tasks, case .browser(let other) = escape {
            check(url.host == "mac.example.ts.net" && url.port == 4310 && url.path == "/tasks" && other.host == "mac.example.ts.net"
                  && !url.absoluteString.contains("sekret") && url.query == nil && url.user == nil,
                  "open plan: the origin is locked and no token or key goes to the browser")
        } else { check(false, "open plan: a card's page is a browser plan") }
    }

    private static func approval(cut: Bool) -> PendingApproval {
        PendingApproval(id: "ap1", messageID: "m1", title: "Send this?", app: "Gmail", fields: [], body: "Hi", bodyCut: cut)
    }
}
