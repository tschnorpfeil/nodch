import Foundation
import Synchronization
import NodchCore

final class ClientStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var mime = "application/json"
        var body = Data()
        var error: URLError? = nil
        var finish = true
    }
    struct State: Sendable {
        var requests: [URLRequest] = []
        var streams: [ClientStub] = []
        var handler: @Sendable (URLRequest) -> Reply = { _ in Reply(status: 500) }
    }
    static let state = Mutex(State())
    static func configure(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0 = State(handler: handler) }
    }
    static var requests: [URLRequest] { state.withLock { $0.requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static func emit(_ text: String) {
        let streams = state.withLock { $0.streams }
        for stream in streams { stream.client?.urlProtocol(stream, didLoad: Data(text.utf8)) }
    }
    override func startLoading() {
        let handler = Self.state.withLock { state in state.requests.append(request); return state.handler }
        let reply = handler(request)
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        if reply.finish { client?.urlProtocolDidFinishLoading(self) }
        else { Self.state.withLock { $0.streams.append(self) } }
    }
    override func stopLoading() { Self.state.withLock { $0.streams.removeAll { $0 === self } } }
}

extension ClientChecks {
    static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        if !predicate() { throw NodClientError.configuration("Timed out waiting for in-process client check") }
    }

    static func transportChecks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = NodClient(configuration: .init(credential: .bearer("fixture")), session: transport)
        let idle = fixture()
        let pending = try NodState.decode(fixture(approval: "pending"))
        var mapper = NodStateMapper()
        guard case .needsYou(let approval, _) = mapper.map(pending) else { return }
        ClientStub.configure { request in
            request.httpMethod == "POST"
                ? .init(status: 409, body: Data("{\"error\":\"This approval is no longer pending.\"}".utf8))
                : .init(body: idle)
        }
        let session = NodSession(client: client)
        do { try await session.answer(approval: approval, approved: true); check(false, "409 handling") }
        catch NodClientError.conflict(let reason) {
            check(reason.contains("no longer pending"), "409 approval throws clear conflict")
        }
        let requests = ClientStub.requests
        check(requests.filter { $0.httpMethod == "POST" }.count == 1 && requests.filter { $0.url?.path == "/api/state" }.count == 1 && session.store.state == .rest, "409 refreshes state without retrying approval")
        if let body = requests.first.map({ request -> Data? in
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return nil }
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }) ?? nil, let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let answer = json["approvalAnswer"] as? [String: Any]
            check(json["replyToMessageId"] as? String == approval.messageID && answer?["approvalId"] as? String == approval.id && answer?["approved"] as? Bool == true && UUID(uuidString: json["clientMessageId"] as? String ?? "") != nil && json["text"] as? String == "Yes", "approval JSON uses message ID, approval ID, explicit decision and client UUID")
            // Nod stores UUIDs lowercase and answers with them: an uppercase id would not match the stored message.
            let id = json["clientMessageId"] as? String ?? ""
            check(id == id.lowercased(), "client message ID is lowercase, as Nod returns it")
        } else { check(false, "approval body present") }
        session.disconnect()

        let snapshot = Mutex(idle)
        ClientStub.configure { request in
            request.url?.path == "/api/events"
                ? .init(mime: "text/event-stream", finish: false)
                : .init(body: snapshot.withLock { $0 })
        }
        let observing = NodSession(client: client)
        observing.start()
        try await eventually { ClientStub.requests.contains { $0.url?.path == "/api/state" } && observing.store.state == .rest }
        for type in ["activity", "working", "refresh"] {
            let before = ClientStub.requests.filter { $0.url?.path == "/api/state" }.count
            snapshot.withLock { $0 = fixture(approval: "pending") }
            ClientStub.emit("data: {\"type\":\"\(type)\"}\n\n")
            try await eventually { ClientStub.requests.filter { $0.url?.path == "/api/state" }.count > before }
            try await eventually { if case .needsYou = observing.store.state { return true }; return false }
            check(true, "SSE \(type) triggers state refetch and mapping")
        }
        let beforeDelta = ClientStub.requests.count
        ClientStub.emit("data: {\"type\":\"delta\"}\n\n")
        try await Task.sleep(for: .milliseconds(50))
        check(ClientStub.requests.count == beforeDelta, "SSE delta does not fetch chat content")
        observing.disconnect()

        ClientStub.configure { _ in .init(status: 401) }
        do { try await session.refresh(); check(false, "401 handling") }
        catch NodClientError.unauthorized {
            if case .offline(let reason) = session.store.state { check(reason.contains("rejected the token"), "401 maps to offline: the token was rejected") }
            else { check(false, "401 offline") }
        }
        ClientStub.configure { _ in .init(error: URLError(.cannotConnectToHost)) }
        do { try await session.send(prompt: "one explicit action", attachments: []); check(false, "network send error") }
        catch NodClientError.network {
            check(ClientStub.requests.count == 1, "network failure never retries send")
            if case .offline = session.store.state { check(true, "unreachable maps to offline") }
            else { check(false, "unreachable offline") }
        }

        ClientStub.configure { _ in .init(error: URLError(.networkConnectionLost)) }
        do { try await session.answer(approval: approval, approved: false); check(false, "network approval error") }
        catch NodClientError.network { check(ClientStub.requests.count == 1, "network failure never retries approval") }
        ClientStub.configure { _ in .init(status: 500, body: Data("{\"error\":\"Unavailable\"}".utf8)) }
        do { _ = try await client.send(prompt: "send once"); check(false, "HTTP mutation error") }
        catch NodClientError.http(500, _) { check(ClientStub.requests.count == 1, "HTTP failure never retries send") }
        ClientStub.configure { _ in .init(body: Data("not JSON".utf8)) }
        do { _ = try await client.state(); check(false, "invalid state response") }
        catch NodClientError.invalidResponse { check(true, "invalid state JSON has a typed error") }

        // Repeated refreshes during the done interval must not postpone the timer. The margins are wide so a slow CI
        // runner cannot fail it: unpostponed, rest comes about 0.4 s after done; postponed, not before 0.65 s.
        let completed = Mutex(fixture(status: "running", activity: true))
        ClientStub.configure { _ in .init(body: completed.withLock { $0 }) }
        let finishing = NodSession(client: client, doneDuration: 0.4)
        try await finishing.refresh()
        completed.withLock { $0 = idle }
        try await finishing.refresh()
        let doneAt = Date()
        check(finishing.store.state == .done(summary: "Finished"), "session publishes completion")
        try await Task.sleep(for: .milliseconds(250))
        try await finishing.refresh()
        for _ in 0..<300 where finishing.store.state != .rest { try await Task.sleep(for: .milliseconds(10)) }
        check(finishing.store.state == .rest && Date().timeIntervalSince(doneAt) < 0.6,
              "session done timer expires without another server event")
        finishing.disconnect()

        // A stream that ends without sending any event must still cause a state GET on
        // every successful connection, including reconnects. All requests stay in-process.
        ClientStub.configure { request in
            request.url?.path == "/api/events"
                ? .init(mime: "text/event-stream", body: Data(": heartbeat\n\n".utf8))
                : .init(body: idle)
        }
        let reconnecting = NodSession(client: client, reconnectBase: 0.02, reconnectCap: 0.04)
        reconnecting.start()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && ClientStub.requests.filter({ $0.url?.path == "/api/state" }).count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        reconnecting.disconnect()
        let reconnectRequests = ClientStub.requests
        check(reconnectRequests.filter { $0.url?.path == "/api/events" }.count >= 3 && reconnectRequests.filter { $0.url?.path == "/api/state" }.count >= 3, "every SSE reconnect refetches state without a refresh event")
        // A request resumed just before `disconnect` reaches the stub (`startLoading`) on URLSession's own thread and
        // may be counted a moment later. Let those land; after that a reconnect loop (every 20–40 ms) would still show.
        try await Task.sleep(for: .milliseconds(100))
        let count = ClientStub.requests.count
        try await Task.sleep(for: .milliseconds(200))
        check(ClientStub.requests.count == count, "disconnect cancels reconnects")

        ClientStub.configure { request in
            request.url?.path == "/api/events"
                ? .init(mime: "text/event-stream", body: Data("data: {\"type\":\"delta\",\"text\":\"ignored\"}\n\ndata: {\"type\":\"activity\"}\n\ndata: {\"type\":\"working\"}\n\ndata: {\"type\":\"refresh\"}\n\n".utf8))
                : .init(body: idle)
        }
        let events = client.events()
        var types: [String] = []
        for try await event in events {
            switch event { case .connected: types.append("connected"); case .update(let type): types.append(type) }
        }
        check(types == ["connected", "delta", "activity", "working", "refresh"], "SSE reads Nod JSON event types rather than relying on event field")
        ClientStub.configure { _ in .init(body: idle) }
        async let first: Void = session.refresh()
        async let second: Void = session.refresh()
        try await first; try await second
        check(ClientStub.requests.count == 1, "concurrent state refreshes coalesce")
        session.disconnect()
    }
}
