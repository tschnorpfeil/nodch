import Foundation

/// The fields consumed from Nod 915e4f1's AppState. Unknown fields remain server-owned. Fields beyond the approval and
/// activity seam are optional, so an older or newer Nod that omits them still decodes.
public struct NodState: Decodable, Sendable {
    public struct Message: Decodable, Sendable {
        public struct Approval: Decodable, Sendable {
            public struct Field: Decodable, Sendable { public let label: String; public let value: String }
            public let id: String
            public let state: String
            public let title: String
            public let app: String
            public let slug: String
            public let fields: [Field]?
            public let body: String?
            public let bodyCut: Bool?
        }
        /// Nod's `AnswerChoices` (src/shared/answer-choices.ts); decoded leniently, Nod validates answers itself.
        public struct AnswerChoices: Decodable, Sendable {
            public struct Option: Decodable, Sendable {
                public let id: String
                public let label: String
                public let description: String?
            }
            public let options: [Option]?
            public let multiple: Bool?
        }
        public let id: String
        public let role: String
        public let text: String
        public let turnId: String?
        public let createdAt: String?
        public let approval: Approval?
        public let answerChoices: AnswerChoices?
        public let answerChoicesPending: Bool?
    }
    public struct Turn: Decodable, Sendable {
        public let id: String
        public let status: String
        public let source: String?
        public let createdAt: String
        public let finishedAt: String?
        public let error: String?
    }
    public struct Activity: Decodable, Sendable {
        public let turnId: String
        public let taskId: String?
        public let title: String?
        public let step: String?
        public let site: String?
        public let since: String
        public let doing: String
        /// Nod's label for a tool without a site, e.g. "Running a command".
        public let tool: String?
        public let background: Bool?
    }
    public let threadId: String
    public let messages: [Message]
    public let turns: [Turn]
    public let activity: [Activity]?
    public let pendingAnswerChoiceMessageIds: [String]?

    public static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}

public struct NodStateMapper: Sendable {
    private var previous: NodState?
    private var doneUntil: Date?
    private var doneSummary: String?
    /// A turn seen failing while connected; failures from before connecting or from proactive turns stay quiet.
    private var failedTurn: String?
    public var doneDuration: TimeInterval

    public init(doneDuration: TimeInterval = 3) { self.doneDuration = doneDuration }

    public mutating func map(_ state: NodState, now: Date = Date()) -> IslandState {
        defer { previous = state }
        if previous?.threadId != state.threadId { doneUntil = nil; previous = nil }
        let approvals = state.messages.compactMap { message -> PendingApproval? in
            guard message.role == "assistant", let approval = message.approval, approval.state == "pending" else { return nil }
            return PendingApproval(id: approval.id, messageID: message.id, title: approval.title, app: approval.app,
                                   fields: (approval.fields ?? []).map { .init(label: $0.label, value: $0.value) },
                                   body: approval.body, bodyCut: approval.bodyCut ?? false,
                                   question: message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message.text)
        }
        if let first = approvals.first { doneUntil = nil; return .needsYou(first, more: approvals.count - 1) }
        // Nod sorts activity by start; the person's own turn wins over older background work.
        if let activity = state.activity?.first(where: { $0.background != true }) ?? state.activity?.first {
            doneUntil = nil
            return .working(WorkActivity(title: activity.title, step: activity.step ?? activity.tool, site: activity.site,
                                         since: Self.date(activity.since) ?? now,
                                         doing: WorkActivity.Doing(rawValue: activity.doing) ?? .model))
        }
        let latest = state.turns.max { $0.createdAt < $1.createdAt }
        if let running = state.turns.first(where: { $0.status == "running" || $0.status == "queued" }) {
            doneUntil = nil
            return .working(WorkActivity(title: nil, step: nil, site: nil, since: Self.date(running.createdAt) ?? now,
                                         doing: running.status == "queued" ? .queued : .model))
        }
        if let latest, latest.status == "failed", latest.source != "event", let previous,
           previous.turns.first(where: { $0.id == latest.id })?.status != "failed" {
            failedTurn = latest.id
        }
        if let latest, latest.status == "failed", failedTurn == latest.id {
            doneUntil = nil
            return .failed(message: latest.error ?? "Nod could not finish this turn.")
        }
        if let latest, latest.status == "succeeded", let previous,
           previous.turns.first(where: { $0.id == latest.id })?.status != "succeeded" {
            doneUntil = now.addingTimeInterval(doneDuration)
            doneSummary = state.messages.last(where: { $0.role == "assistant" && $0.turnId == latest.id })?.text
        }
        if let until = doneUntil, now < until { return .done(summary: doneSummary) }
        return .rest
    }

    /// Nod's latest answer: the newest assistant message with nonempty text and without an approval card (that one is
    /// shown as `.needsYou`). Messages of a running or queued turn are skipped: Nod refreshes state while the turn works,
    /// and its text can still change or grow, so the panel would flicker through half-written answers. The last finished
    /// answer stays until the turn ends. A turn waiting on a question has status "waiting", so open questions still show.
    public func answer(_ state: NodState) -> NodAnswer? {
        let busy = Set(state.turns.filter { $0.status == "running" || $0.status == "queued" }.map(\.id))
        let pendingIDs = Set(state.pendingAnswerChoiceMessageIds ?? [])
        let latest = state.messages.enumerated()
            .filter { _, message in
                message.role == "assistant" && message.approval == nil
                    && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !(message.turnId.map(busy.contains) ?? false)
            }
            // Nod lists messages oldest first; createdAt decides, the list order breaks ties.
            .max { lhs, rhs in
                let left = lhs.element.createdAt.flatMap(Self.date) ?? .distantPast
                let right = rhs.element.createdAt.flatMap(Self.date) ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left < right
            }?.element
        guard let latest else { return nil }
        var question: NodQuestion?
        if let choices = latest.answerChoices, let options = choices.options, !options.isEmpty,
           latest.answerChoicesPending == true || pendingIDs.contains(latest.id) {
            question = NodQuestion(choices: options.map { .init(id: $0.id, label: $0.label, detail: $0.description) },
                                   multiple: choices.multiple ?? false)
        }
        return NodAnswer(id: latest.id, text: latest.text, at: latest.createdAt.flatMap(Self.date) ?? .distantPast,
                         question: question)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
