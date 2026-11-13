import Foundation

/// The fields consumed from Nod 915e4f1's AppState. Unknown fields remain server-owned.
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
        public let id: String
        public let role: String
        public let text: String
        public let turnId: String?
        public let approval: Approval?
    }
    public struct Turn: Decodable, Sendable {
        public let id: String
        public let status: String
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
        public let background: Bool?
    }
    public let threadId: String
    public let messages: [Message]
    public let turns: [Turn]
    public let activity: [Activity]?

    public static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}

public struct NodStateMapper: Sendable {
    private var previous: NodState?
    private var doneUntil: Date?
    private var doneSummary: String?
    public var doneDuration: TimeInterval

    public init(doneDuration: TimeInterval = 3) { self.doneDuration = doneDuration }

    public mutating func map(_ state: NodState, now: Date = Date()) -> IslandState {
        defer { previous = state }
        if previous?.threadId != state.threadId { doneUntil = nil; previous = nil }
        let approvals = state.messages.compactMap { message -> PendingApproval? in
            guard message.role == "assistant", let approval = message.approval, approval.state == "pending" else { return nil }
            return PendingApproval(id: approval.id, messageID: message.id, title: approval.title, app: approval.app,
                                   fields: (approval.fields ?? []).map { .init(label: $0.label, value: $0.value) },
                                   body: approval.body, bodyCut: approval.bodyCut ?? false)
        }
        if let first = approvals.first { doneUntil = nil; return .needsYou(first, more: approvals.count - 1) }
        if let activity = state.activity?.first {
            doneUntil = nil
            return .working(WorkActivity(title: activity.title, step: activity.step, site: activity.site,
                                         since: Self.date(activity.since) ?? now,
                                         doing: WorkActivity.Doing(rawValue: activity.doing) ?? .model))
        }
        let latest = state.turns.max { $0.createdAt < $1.createdAt }
        if let running = state.turns.first(where: { $0.status == "running" || $0.status == "queued" }) {
            doneUntil = nil
            return .working(WorkActivity(title: nil, step: nil, site: nil, since: Self.date(running.createdAt) ?? now,
                                         doing: running.status == "queued" ? .queued : .model))
        }
        if let latest, latest.status == "failed" {
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

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
