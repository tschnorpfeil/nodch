import Foundation
import NodchCore

@MainActor enum ClientChecks {
    static func run() async {
        parserChecks()
        mappingChecks()
        do { try configurationChecks(); try await transportChecks() }
        catch { check(false, "client checks: \(error)") }
    }

    static func parserChecks() {
        var parser = SSEParser()
        let wire = "\u{FEFF}: heartbeat\r\nevent: refresh\r\nid: 42\r\ndata: first 🦉\r\ndata:second\r\n\r\n:keepalive\n\ndata:\n\nevent: discarded\n\nevent: activity\rdata: {\"type\":\"activity\"}\r\rdata: unfinished"
        var events: [SSEEvent] = []
        // Every UTF-8 byte, including emoji and CRLF, arrives in a separate chunk.
        for byte in wire.utf8 { events += parser.append(Data([byte])) }
        check(events.count == 3, "SSE partial UTF-8, CR/LF/CRLF, BOM and heartbeats")
        check(events.first?.data == "first 🦉\nsecond" && events.first?.event == "refresh" && events.first?.id == "42", "SSE multiline data and event/id fields")
        check(events.dropFirst().first?.data == "" && events.dropFirst().first?.event == "message", "SSE empty data dispatches; event without data resets")
        check(events.last?.event == "activity", "SSE partial trailing event is not dispatched")
        var batch = SSEParser()
        check(batch.append(Data("data: a\n\ndata: b\n\n".utf8)).map(\.data) == ["a", "b"], "SSE multiple events in one chunk")
    }

    // Matches src/shared/contracts.ts and GET /api/state at Nod 915e4f1.
    static func fixture(status: String = "succeeded", approval: String? = nil, activity: Bool = false,
                        thread: String = "00000000-0000-4000-8000-000000000001") -> Data {
        let card = approval.map { ",\"approval\":{\"id\":\"00000000-0000-4000-8000-000000000004\",\"state\":\"\($0)\",\"title\":\"Pause notifications?\",\"app\":\"Nod\",\"slug\":\"nod\",\"fields\":[{\"label\":\"Paused\",\"value\":\"Yes\"}],\"body\":\"Preview\",\"bodyCut\":true}" } ?? ""
        return Data("""
        {"threadId":"\(thread)","hasEarlierMessages":false,"hiddenMessageCount":0,"hiddenMessageIds":[],"pendingAnswerChoiceMessageIds":[],"messages":[{"id":"00000000-0000-4000-8000-000000000003","role":"assistant","text":"Finished","turnId":"00000000-0000-4000-8000-000000000002","createdAt":"2026-11-13T08:00:00.000Z","attachments":[]\(card)}],"turns":[{"id":"00000000-0000-4000-8000-000000000002","status":"\(status)","source":"user","createdAt":"2026-11-13T08:00:00.000Z","finishedAt":null,"error":\(status == "failed" ? "\"Model failed\"" : "null")}],"activity":[\(activity ? "{\"turnId\":\"00000000-0000-4000-8000-000000000002\",\"taskId\":null,\"title\":\"Checking\",\"step\":\"Reading\",\"site\":\"example.org\",\"since\":\"2026-11-13T08:00:00.125Z\",\"doing\":\"tool\",\"quietSince\":\"2026-11-13T08:00:00.125Z\"}" : "")],"verificationRequests":[],"planningTasks":false,"configuration":{"provider":"compatible","model":"nodch-contract","llmReady":true,"modelReconnect":false,"integrationsReady":false,"conversationResetEnabled":true}}
        """.utf8)
    }

    static func mappingChecks() {
        do {
            var mapper = NodStateMapper(doneDuration: 2)
            let now = Date()
            check(mapper.map(try .decode(fixture()), now: now) == .rest, "state ignores historical completion on initial connect")
            let running = try NodState.decode(fixture(status: "running", activity: true))
            if case .working(let work) = mapper.map(running, now: now) {
                check(work.doing == .tool && work.site == "example.org" && work.title == "Checking" && abs(work.since.timeIntervalSince1970 - 1794556800.125) < 0.01, "state maps real Activity fields and fractional timestamp")
            } else { check(false, "state maps Activity") }
            let pending = try NodState.decode(fixture(status: "running", approval: "pending", activity: true))
            if case .needsYou(let approval, let more) = mapper.map(pending, now: now) {
                check(approval.messageID.hasSuffix("3") && approval.id.hasSuffix("4") && more == 0 && approval.bodyCut && approval.fields.first?.value == "Yes", "pending approval wins over running activity")
            } else { check(false, "pending approval wins") }
            var duplicate = try JSONSerialization.jsonObject(with: fixture(approval: "pending")) as! [String: Any]
            duplicate["messages"] = (duplicate["messages"] as! [[String: Any]]) + (duplicate["messages"] as! [[String: Any]])
            if case .needsYou(_, let more) = mapper.map(try .decode(JSONSerialization.data(withJSONObject: duplicate)), now: now) {
                check(more == 1, "state counts additional pending approvals")
            } else { check(false, "multiple approvals") }
            _ = mapper.map(running, now: now)
            let finished = try NodState.decode(fixture())
            check(mapper.map(finished, now: now) == .done(summary: "Finished"), "newly completed turn shows done")
            check(mapper.map(finished, now: now.addingTimeInterval(1)) == .done(summary: "Finished"), "refresh does not extend completion deadline")
            check(mapper.map(finished, now: now.addingTimeInterval(3)) == .rest, "done expires to rest")
            check(mapper.map(try .decode(fixture(status: "failed"))) == .failed(message: "Model failed"), "failed turn exposes server error")
            for status in ["working", "done", "declined", "expired", "uncertain"] {
                var fresh = NodStateMapper()
                check(fresh.map(try .decode(fixture(approval: status))) == .rest, "approval state \(status) is not pending")
            }
            var fresh = NodStateMapper()
            if case .working(let work) = fresh.map(try .decode(fixture(status: "queued"))) {
                check(work.doing == .queued, "queued turn maps without activity")
            } else { check(false, "queued turn maps") }
            _ = fresh.map(running)
            check(fresh.map(try .decode(fixture(thread: "another-thread"))) == .rest, "thread change does not announce old completion")
        } catch { check(false, "JSON fixtures decode: \(error)") }
    }

    static func configurationChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nodch-contract/checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = String(repeating: "a", count: 43)
        try key.write(to: directory.appendingPathComponent("access-key"), atomically: true, encoding: .utf8)
        let cookie = try NodConfiguration.fromEnvironment(["NOD_DATA_ROOT": directory.path])
        let cookieRequest = try cookie.request(path: "/api/state")
        check(cookie.baseURL.port == 4310 && cookieRequest.value(forHTTPHeaderField: "Cookie") == "nod-access-4310=\(key)" && cookieRequest.value(forHTTPHeaderField: "Authorization") == nil, "access-key file builds Nod port cookie; default port is 4310")
        let bearer = try NodConfiguration.fromEnvironment(["NOD_URL": "http://localhost:5432", "NOD_AUTH_TOKEN": "token", "NOD_DATA_ROOT": "/unavailable"])
        let request = try bearer.request(path: "/api/state")
        check(request.value(forHTTPHeaderField: "Authorization") == "Bearer token" && request.value(forHTTPHeaderField: "Cookie") == nil && request.url?.host == "localhost", "bearer takes precedence over access-key file and preserves host")
        check(bearer.browserURL(path: "https://other.example/vault").host == "localhost" && bearer.browserURL(path: "/vault").path == "/vault", "openNod paths stay on configured server")
        do { _ = try NodConfiguration.fromEnvironment(["NOD_URL": "file:///etc/passwd"]); check(false, "invalid configuration rejected") }
        catch { check(true, "invalid configuration rejected") }
        do { _ = try NodConfiguration.fromEnvironment(["NOD_DATA_ROOT": directory.appendingPathComponent("missing").path]).request(path: "/api/state"); check(false, "missing credentials") }
        catch NodClientError.credentials { check(true, "missing access-key reports credentials") }
    }
}
