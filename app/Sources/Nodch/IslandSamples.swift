import Foundation
import NodchCore

/// Made-up states for `--demo` and `--snapshot`. Nothing here comes from or goes to a real Nod.
enum IslandSamples {
    static func working(step: String? = "Reading the latest invoices", site: String? = "mail.google.com",
                        title: String? = "Prepare the November expense report", seconds: TimeInterval = 42) -> IslandState {
        .working(WorkActivity(title: title, step: step, site: site, since: Date().addingTimeInterval(-seconds), doing: .tool))
    }

    static let email = PendingApproval(
        id: "demo-approval-1", messageID: "demo-message-1", title: "Send this email?", app: "Gmail",
        fields: [.init(label: "To", value: "finance@example.com"),
                 .init(label: "Subject", value: "November expense report")],
        body: """
        Hi team,

        attached is the expense report for November. Totals: 1,284.50 EUR across 14 receipts. \
        Two receipts are still missing; I'll send them by Friday.

        Thanks!
        """,
        bodyCut: false,
        question: "I drafted the November expense report. Send it to finance now?")

    /// Many long fields and a long question on top of a long body: the decision row must stay reachable.
    static let tall = PendingApproval(
        id: "demo-approval-4", messageID: "demo-message-4", title: "Send this invitation to the whole launch group?", app: "Gmail",
        fields: (1...12).map { .init(label: "To \($0)", value: "launch-team-member-\($0)@a-long-company-domain.example.com") },
        body: longPost.body, bodyCut: false,
        question: String(repeating: "Nod prepared the invitation with every attendee from the planning sheet. ", count: 4) + "Send it now?")

    static let longPost = PendingApproval(
        id: "demo-approval-2", messageID: "demo-message-2", title: "Publish this post to the team channel?", app: "Slack",
        fields: [.init(label: "Channel", value: "#launch-coordination"),
                 .init(label: "As", value: "you")],
        body: (1...9).map { n in
            "\(n). " + [
                "The release candidate passed the full regression suite on all three platforms overnight.",
                "Docs for the new connectors are merged; screenshots still need a refresh before Thursday.",
                "Support asked for a short FAQ on the pricing change, especially for annual plans.",
                "The migration script was tested against a copy of the largest workspace and finished in 11 minutes.",
                "Marketing wants the announcement at 16:00 CET so it lands before the US morning.",
                "We keep the old endpoint for 90 days and log every call so we can reach out to remaining users.",
                "On-call for launch week is Priya, then Jonas; escalation goes to the platform channel.",
                "Rollback plan: flip the feature flag, then redeploy the previous image if errors stay above 1 %.",
                "Thanks everyone. This one was a team effort from the first design doc to the last bug bash.",
            ][n - 1]
        }.joined(separator: "\n\n"),
        bodyCut: false)

    static let cutNote = PendingApproval(
        id: "demo-approval-3", messageID: "demo-message-3", title: "Create this calendar event?", app: "Google Calendar",
        fields: [.init(label: "When", value: "Tue, 17 Nov, 10:00 – 10:45"),
                 .init(label: "Guests", value: "ana@example.com, ben@example.com, chris@example.com")],
        body: "Agenda: review Q4 numbers, agree on the hiring plan, and decide which of the three vendor offers we take forward. "
            + "Please read the attached one-pager before the call; it covers the cost comparison and the",
        bodyCut: true)

    // Quick prompts, built through the same steps the app takes.

    static var failedSend: PromptDraft {
        var draft = PromptDraft(text: "Summarise my unread mail from today")
        _ = draft.submit()
        draft.sendFailed("Nod didn’t accept the message: the server answered 503.")
        return draft
    }

    /// Opened with the shortcut: some words final, the latest still being recognized.
    static var listening: PromptDraft {
        var draft = PromptDraft()
        _ = draft.open(.hotkey)
        draft.voiceStarted()
        draft.heard("Please summarize my unread email", final: true)
        draft.heard("from today and flag anything urgent", final: false)
        return draft
    }

    static var voiceDenied: PromptDraft {
        var draft = PromptDraft()
        _ = draft.open(.hotkey)
        draft.voiceUnavailable(.microphoneDenied)
        return draft
    }

    /// Three dropped files: one uploaded, one still uploading, one refused.
    static var attachments: PromptDraft {
        var draft = PromptDraft(text: "What do these say about Q4?")
        let folder = URL(fileURLWithPath: "/Users/demo/Documents", isDirectory: true)
        _ = draft.drop(["Q4 report.pdf", "receipts-november.zip", "Board deck final v7 (copy).key"].map {
            DroppedFile(url: folder.appendingPathComponent($0), isDirectory: false)
        })
        draft.uploaded(1, as: NodAttachment(id: "demo-upload-1", name: "Q4 report.pdf", mimeType: "application/pdf", size: 482_133))
        draft.uploadFailed(3, reason: "Nod refused it: larger than 25 MB.")
        return draft
    }

    static let failed = IslandState.failed(message: "The browser session expired while filling in the form. Sign in again in Nod, then retry from there.")
    static let offline = IslandState.offline(reason: "Nod isn’t running, or it doesn’t answer on localhost.")
    static let done = IslandState.done(summary: "Expense report sent to finance")
}

/// Fake actions for `--demo`: they log what a real session would send to Nod and move the demo along, nothing else.
@MainActor
final class DemoActions: NodActions {
    weak var store: IslandStore?
    var failNextSend = true

    func send(prompt: String, attachments: [NodAttachment]) async throws {
        print("demo: send(prompt: \"\(prompt)\", attachments: \(attachments.map(\.name)))")
        try await Task.sleep(for: .milliseconds(450))
        // The first send fails once, so the inline error can be seen; the next one goes through.
        if failNextSend {
            failNextSend = false
            throw DemoError(message: "Nod didn’t accept the message (demo: the first send fails on purpose). Press Return to try again.")
        }
        store?.state = IslandSamples.working(step: "Thinking about: \(prompt)", site: nil, title: prompt, seconds: 0)
    }

    func answer(approval: PendingApproval, approved: Bool) async throws {
        print("demo: answer(approval: \(approval.id), approved: \(approved))")
        try await Task.sleep(for: .milliseconds(400))
        store?.state = approved ? IslandSamples.working(step: "Doing what you approved", site: nil, title: approval.title, seconds: 0)
                                : .done(summary: "Declined: \(approval.title)")
    }

    func upload(file: URL) async throws -> NodAttachment {
        print("demo: upload(file: \(file.lastPathComponent))")
        try await Task.sleep(for: .milliseconds(350))
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return NodAttachment(id: UUID().uuidString.lowercased(), name: file.lastPathComponent, mimeType: "application/octet-stream", size: size)
    }

    func stop() async throws {
        print("demo: stop()")
        try await Task.sleep(for: .milliseconds(300))
        store?.state = .done(summary: "Stopped")
    }

    func openNod(path: String) {
        print("demo: openNod(path: \"\(path)\")")
    }

    struct DemoError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
}

/// `--demo`: every state in turn, on a loop. Each step waits a little longer while an approval is open, so there is
/// time to read it; answering one moves on through `DemoActions`.
@MainActor
final class DemoScript {
    let store: IslandStore
    let actions = DemoActions()
    private var task: Task<Void, Never>?

    init(store: IslandStore) {
        self.store = store
        actions.store = store
    }

    func start() {
        print("demo: cycling through every state; ⌥Space opens the quick prompt. Ctrl-C to quit.")
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                for (seconds, state) in Self.steps() {
                    print("demo: state → \(Self.name(state))")
                    store.state = state
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
        }
    }

    private static func steps() -> [(Double, IslandState)] {
        [
            (4, IslandSamples.offline),
            (4, .rest),
            (3, IslandSamples.working(step: nil, site: nil, title: "Prepare the November expense report", seconds: 0)),
            (4, IslandSamples.working(step: "Reading the latest invoices", site: "mail.google.com", seconds: 3)),
            (10, .needsYou(IslandSamples.email, more: 0)),
            (4, IslandSamples.working(step: "Filling in the expense form", site: "expenses.example.com", seconds: 21)),
            (10, .needsYou(IslandSamples.longPost, more: 2)),
            (10, .needsYou(IslandSamples.cutNote, more: 1)),
            (5, IslandSamples.done),
            (4, .rest),
            (6, IslandSamples.failed),
        ]
    }

    private static func name(_ state: IslandState) -> String {
        switch state {
        case .offline: "offline"
        case .rest: "rest"
        case .working(let a): "working(\(a.step ?? a.title ?? "-"))"
        case .needsYou(let a, let more): "needsYou(\(a.id), more: \(more))"
        case .done: "done"
        case .failed: "failed"
        }
    }
}
