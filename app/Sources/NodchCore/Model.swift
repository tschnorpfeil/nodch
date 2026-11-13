import Foundation
import Observation

// The seam between the Nod client (Client/) and the island UI (the Nodch target and Island/).
// The client writes `IslandStore.state`; the UI only reads it and calls `NodActions`.

/// What Nod is doing, mapped from Nod's `Activity` (src/shared/contracts.ts).
public struct WorkActivity: Equatable, Sendable {
    public enum Doing: String, Sendable { case queued, model, tool }
    public var title: String?
    public var step: String?
    public var site: String?
    public var since: Date
    public var doing: Doing

    public init(title: String?, step: String?, site: String?, since: Date, doing: Doing) {
        self.title = title; self.step = step; self.site = site; self.since = since; self.doing = doing
    }
}

/// A pending approval, mapped from Nod's `MessageApproval` with `state == "pending"`.
public struct PendingApproval: Equatable, Sendable, Identifiable {
    public struct Field: Equatable, Sendable { public var label: String; public var value: String
        public init(label: String, value: String) { self.label = label; self.value = value } }
    public var id: String
    /// The message that carries the approval; Nod expects it as `replyToMessageId`.
    public var messageID: String
    public var title: String
    /// The question Nod asks in the message that carries the approval, e.g. "Pause proactive notifications? …".
    public var question: String?
    public var app: String
    public var fields: [Field]
    public var body: String?
    /// Nod cut the body; the full text is only in Nod's window.
    public var bodyCut: Bool

    public init(id: String, messageID: String, title: String, app: String, fields: [Field], body: String?, bodyCut: Bool,
                question: String? = nil) {
        self.id = id; self.messageID = messageID; self.title = title; self.question = question; self.app = app
        self.fields = fields; self.body = body; self.bodyCut = bodyCut
    }
}

public enum IslandState: Equatable, Sendable {
    /// Nod cannot be reached or rejected the credentials.
    case offline(reason: String)
    /// Connected, nothing going on.
    case rest
    case working(WorkActivity)
    /// Nod waits for the user. `more` counts further pending approvals.
    case needsYou(PendingApproval, more: Int)
    /// A turn just finished; the UI shows it briefly, then returns to rest.
    case done(summary: String?)
    case failed(message: String)
}

/// Everything the UI may ask of Nod. Each call is one explicit user action; implementations never retry an approval.
@MainActor public protocol NodActions: AnyObject {
    func send(prompt: String) async throws
    func answer(approval: PendingApproval, approved: Bool) async throws
    func stop() async throws
    /// Opens Nod's own window, e.g. "/" or "/vault".
    func openNod(path: String)
}

@MainActor @Observable public final class IslandStore {
    public var state: IslandState
    public weak var actions: NodActions?

    public init(state: IslandState = .offline(reason: "Not connected")) { self.state = state }
}
