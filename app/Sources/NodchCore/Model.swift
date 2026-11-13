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

/// A file uploaded to Nod and not yet sent, mapped from Nod's `Artifact` (POST /api/uploads). Nod keeps an upload for
/// a day; it goes out as one of the message's `attachmentIds`.
public struct NodAttachment: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var mimeType: String
    public var size: Int

    public init(id: String, name: String, mimeType: String, size: Int) {
        self.id = id; self.name = name; self.mimeType = mimeType; self.size = size
    }
}

/// A question Nod waits on, mapped from a message's `answerChoices` (src/shared/answer-choices.ts).
public struct NodQuestion: Equatable, Sendable {
    public struct Choice: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        /// Nod's optional `description` for the choice.
        public var detail: String?

        public init(id: String, label: String, detail: String? = nil) { self.id = id; self.label = label; self.detail = detail }
    }
    public var choices: [Choice]
    /// The person may pick several choices; otherwise exactly one, or only their own words.
    public var multiple: Bool

    public init(choices: [Choice], multiple: Bool) { self.choices = choices; self.multiple = multiple }
}

/// Nod's latest answer in the conversation: the newest assistant message with text and without an approval.
public struct NodAnswer: Equatable, Sendable, Identifiable {
    /// The message id; Nod expects it as `replyToMessageId` when the person answers the question.
    public var id: String
    /// Full text, Markdown as Nod wrote it.
    public var text: String
    public var at: Date
    /// Set only while Nod waits for the person to pick (answerChoicesPending, or listed in pendingAnswerChoiceMessageIds).
    public var question: NodQuestion?

    public init(id: String, text: String, at: Date, question: NodQuestion? = nil) {
        self.id = id; self.text = text; self.at = at; self.question = question
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
    /// Nod asked a question with answer choices and waits for the person's pick or own words.
    case asks(NodAnswer)
    /// A turn just finished; the UI shows it briefly, then returns to rest.
    case done(summary: String?)
    case failed(message: String)
}

/// Everything the UI may ask of Nod. Each call is one explicit user action; implementations never retry an approval.
@MainActor public protocol NodActions: AnyObject {
    /// Sends one message. `attachments` were uploaded with `upload(file:)`; the text may be empty when there are some.
    func send(prompt: String, attachments: [NodAttachment]) async throws
    /// Uploads one file the person dropped on the island. Nothing is sent until they send the prompt.
    func upload(file: URL) async throws -> NodAttachment
    func answer(approval: PendingApproval, approved: Bool) async throws
    /// Answers Nod's open question with the picked `choices` and/or the person's own `text`. One action per click, never repeated.
    func answer(question: NodAnswer, choices: [NodQuestion.Choice], text: String) async throws
    func stop() async throws
    /// Opens Nod's own window, e.g. "/" or "/vault".
    func openNod(path: String)
}

@MainActor @Observable public final class IslandStore {
    public var state: IslandState
    /// Nod's latest answer, set on every state fetch.
    public var answer: NodAnswer?
    public weak var actions: NodActions?

    public init(state: IslandState = .offline(reason: "Not connected"), answer: NodAnswer? = nil) {
        self.state = state; self.answer = answer
    }
}
