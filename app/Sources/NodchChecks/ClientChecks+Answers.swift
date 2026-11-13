import Foundation
import NodchCore

extension ClientChecks {
    nonisolated static let questionID = "00000000-0000-4000-8000-000000000012"
    nonisolated static let soonID = "00000000-0000-4000-8000-0000000000c1"
    nonisolated static let laterID = "00000000-0000-4000-8000-0000000000c2"

    // Matches Message and AppState in src/shared/contracts.ts at Nod 915e4f1. A turn waiting on a question has status
    // "waiting" (src/server/answer-choices.ts `pendingAnswerChoicesSql`).
    nonisolated static func answerFixture(pending: Bool? = true, listed: Bool = false, running: Bool = true) -> Data {
        let flag = pending.map { ",\"answerChoicesPending\":\($0)" } ?? ""
        let message = { (id: String, turn: String, at: String, text: String, extra: String) in
            "{\"id\":\"00000000-0000-4000-8000-0000000000\(id)\",\"role\":\"assistant\",\"text\":\"\(text)\",\"turnId\":\"00000000-0000-4000-8000-0000000000\(turn)\",\"createdAt\":\"2026-11-13T08:\(at):00.000Z\",\"attachments\":[]\(extra)}"
        }
        let messages = [
            message("10", "a1", "00", "Older answer", ""),
            "{\"id\":\"00000000-0000-4000-8000-000000000011\",\"role\":\"user\",\"text\":\"When should I book it?\",\"turnId\":\"00000000-0000-4000-8000-0000000000a2\",\"createdAt\":\"2026-11-13T08:01:00.000Z\",\"attachments\":[]}",
            message("12", "a2", "02", "## When?\\n\\nI can book **today** or later.", ",\"answerChoices\":{\"options\":[{\"id\":\"\(soonID)\",\"label\":\"Tomorrow\",\"description\":\"Friday morning\"},{\"id\":\"\(laterID)\",\"label\":\"Later\",\"description\":\"later\"}],\"multiple\":true}\(flag)"),
            // An approval card is shown as needsYou, not as the answer.
            message("13", "a2", "03", "Pause proactive notifications?", ",\"approval\":{\"id\":\"00000000-0000-4000-8000-000000000004\",\"state\":\"done\",\"title\":\"Pause\",\"app\":\"Nod\",\"slug\":\"nod\"}"),
            message("14", "a2", "04", " \\n ", ""),
            message("15", "a3", "05", "Half-writ", ""),
            // Listed last but older: createdAt decides, not the list position.
            message("16", "a1", "00", "Oldest, listed last", ""),
        ].joined(separator: ",")
        let turns = [("a1", "succeeded"), ("a2", "waiting"), ("a3", running ? "running" : "succeeded")].map { id, status in
            "{\"id\":\"00000000-0000-4000-8000-0000000000\(id)\",\"status\":\"\(status)\",\"source\":\"user\",\"createdAt\":\"2026-11-13T08:00:00.000Z\",\"finishedAt\":null,\"error\":null}"
        }.joined(separator: ",")
        return Data("""
        {"threadId":"00000000-0000-4000-8000-000000000001","hasEarlierMessages":false,"pendingAnswerChoiceMessageIds":[\(listed ? "\"\(questionID)\"" : "")],"messages":[\(messages)],"turns":[\(turns)],"activity":[],"configuration":{"llmReady":true},"futureField":{"unknown":1}}
        """.utf8)
    }

    static func answerMappingChecks() {
        do {
            let state = try NodState.decode(answerFixture())
            let question = state.messages.first { $0.id == questionID }
            check(question?.answerChoices?.options?.first?.description == "Friday morning" && question?.answerChoices?.multiple == true && question?.answerChoicesPending == true && question?.createdAt == "2026-11-13T08:02:00.000Z" && state.pendingAnswerChoiceMessageIds == [], "state decodes answerChoices, answerChoicesPending, createdAt and pendingAnswerChoiceMessageIds")
            check((try? NodState.decode(fixture(approval: "pending"))) != nil, "state without answer fields still decodes")

            let mapper = NodStateMapper()
            let answer = mapper.answer(state)
            check(answer?.id == questionID && answer?.text == "## When?\n\nI can book **today** or later." && abs((answer?.at.timeIntervalSince1970 ?? 0) - 1794556920) < 0.01, "answer is the newest finished assistant text in full; approval, blank and running-turn messages are skipped")
            check(answer?.question == NodQuestion(choices: [.init(id: soonID, label: "Tomorrow", detail: "Friday morning"), .init(id: laterID, label: "Later", detail: "later")], multiple: true), "a pending question carries its choices")
            check(mapper.answer(try .decode(answerFixture(running: false)))?.text == "Half-writ", "the running turn's answer shows once the turn finished")
            let answered = mapper.answer(try .decode(answerFixture(pending: false))), unflagged = mapper.answer(try .decode(answerFixture(pending: nil)))
            check(answered?.id == questionID && answered?.question == nil && unflagged?.question == nil, "an answered question has no question")
            check(mapper.answer(try .decode(answerFixture(pending: nil, listed: true)))?.question?.choices.count == 2, "pendingAnswerChoiceMessageIds alone marks the question open")
            check(mapper.answer(try .decode(fixture(status: "running"))) == nil, "no answer while the only one belongs to a running turn")
            var done = NodStateMapper()
            _ = done.map(try .decode(fixture(status: "running")))
            check(done.map(try .decode(fixture())) == .done(summary: "Finished"), "done summary stays the full last text of the turn")
        } catch { check(false, "answer fixtures decode: \(error)") }
    }

    static func answerChecks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = NodClient(configuration: .init(credential: .bearer("fixture")), session: transport)
        let session = NodSession(client: client)
        defer { session.disconnect() }
        let state = answerFixture()
        let submission = Data("{\"threadId\":\"thread\",\"turnId\":\"turn\",\"messageId\":\"message\"}".utf8)
        ClientStub.configure { request in .init(body: request.httpMethod == "POST" ? submission : state) }
        try await session.refresh()
        guard let answer = session.store.answer, let question = answer.question else {
            check(false, "session publishes the answer on refresh"); return
        }
        check(answer.id == questionID, "session publishes the answer on refresh")
        let soon = question.choices[0], later = question.choices[1]

        // Nod 915e4f1 src/server/thread.ts: only picks → text == choiceAnswerText(picks); picks + custom →
        // writtenAnswer(picks, text) is nonempty; custom only → nonempty text. All need replyToMessageId.
        let cases: [(String, [NodQuestion.Choice], String, String, [String]?, Bool?)] = [
            ("only picks", [later, soon], "", "Tomorrow: Friday morning\nLater", [soonID, laterID], nil),
            ("picks and own words", [soon], "  At 9, please \n", "Tomorrow: Friday morning\nAt 9, please", [soonID], true),
            ("only own words", [], " At 9 ", "At 9", nil, true),
        ]
        for (name, choices, text, expected, ids, custom) in cases {
            ClientStub.configure { request in .init(body: request.httpMethod == "POST" ? submission : state) }
            try await session.answer(question: answer, choices: choices, text: text)
            let posts = ClientStub.requests.filter { $0.httpMethod == "POST" }
            guard posts.count == 1, posts[0].url?.path == "/api/messages",
                  let json = try JSONSerialization.jsonObject(with: requestBody(posts[0])) as? [String: Any] else {
                check(false, "question answer \(name): one POST /api/messages"); continue
            }
            let selection = json["questionAnswer"] as? [String: Any] ?? [:]
            let id = json["clientMessageId"] as? String ?? ""
            check(json["text"] as? String == expected && json["replyToMessageId"] as? String == questionID
                  && selection["choiceIds"] as? [String] == ids && selection["custom"] as? Bool == custom
                  && selection.count == (ids == nil ? 0 : 1) + (custom == nil ? 0 : 1)
                  && json["approvalAnswer"] == nil && UUID(uuidString: id) != nil && id == id.lowercased(),
                  "question answer \(name): text, replyToMessageId and questionAnswer as Nod's web app sends them")
            try await eventually { ClientStub.requests.contains { $0.url?.path == "/api/state" } }
        }

        let single = NodAnswer(id: questionID, text: answer.text, at: answer.at, question: NodQuestion(choices: question.choices, multiple: false))
        let invalid: [(String, NodAnswer, [NodQuestion.Choice], String)] = [
            ("no pick and blank text", answer, [], " \n "),
            ("a pick Nod did not offer", answer, [.init(id: "00000000-0000-4000-8000-0000000000ff", label: "Other")], ""),
            ("two picks on a single-choice question", single, [soon, later], ""),
            ("a pick and own words on a single-choice question", single, [soon], "and more"),
            ("a message without an open question", NodAnswer(id: questionID, text: "Done", at: answer.at), [soon], ""),
        ]
        for (name, target, choices, text) in invalid {
            ClientStub.configure { _ in .init(body: submission) }
            do { try await session.answer(question: target, choices: choices, text: text); check(false, "question answer with \(name) is rejected") }
            catch NodClientError.invalidInput { check(!ClientStub.requests.contains { $0.httpMethod == "POST" }, "question answer with \(name) sends nothing") }
        }

        ClientStub.configure { request in
            request.httpMethod == "POST"
                ? .init(status: 409, body: Data("{\"code\":\"question_unavailable\",\"error\":\"This question is no longer waiting for an answer.\"}".utf8))
                : .init(body: answerFixture(pending: false))
        }
        do { try await session.answer(question: answer, choices: [soon], text: ""); check(false, "409 question_unavailable") }
        catch NodClientError.conflict(let reason) {
            let requests = ClientStub.requests
            check(reason.contains("no longer waiting") && requests.filter { $0.httpMethod == "POST" }.count == 1
                  && requests.filter { $0.url?.path == "/api/state" }.count == 1 && session.store.answer?.question == nil,
                  "409 question_unavailable throws conflict, refreshes state and never repeats the answer")
        }
    }
}
