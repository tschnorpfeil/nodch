import Foundation
import Synchronization
import NodchCore

extension ClientChecks {
    /// A failed state GET must not leave the island offline while the event stream stays connected and quiet.
    static func retryChecks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = NodClient(configuration: .init(credential: .bearer("fixture")), session: transport)
        let idle = fixture()
        func stateGETs() -> Int { ClientStub.requests.filter { $0.url?.path == "/api/state" }.count }

        // First GET fails (503, then a dropped connection), the next succeeds: no event arrives in between.
        for failure in [ClientStub.Reply(status: 503, body: Data("{\"error\":\"Unavailable\"}".utf8)), .init(error: URLError(.networkConnectionLost))] {
            let calls = Mutex(0)
            ClientStub.configure { request in
                if request.url?.path == "/api/events" { return .init(mime: "text/event-stream", finish: false) }
                return calls.withLock { $0 += 1; return $0 } == 1 ? failure : .init(body: idle)
            }
            let session = NodSession(client: client, retryBase: 0.02, retryCap: 0.08)
            session.start()
            try await eventually { stateGETs() >= 2 && session.store.state == .rest }
            check(true, "failed state GET is retried without another event and clears offline (\(failure.status == 503 ? "503" : "network"))")
            let settled = stateGETs()
            try await Task.sleep(for: .milliseconds(200))
            check(stateGETs() == settled, "no more state GETs once the retry succeeds")
            session.disconnect()
        }

        // Backoff doubles up to the cap and a new event cuts the wait short.
        let healthy = Mutex(false)
        ClientStub.configure { request in
            if request.url?.path == "/api/events" { return .init(mime: "text/event-stream", finish: false) }
            return healthy.withLock { $0 } ? .init(body: idle) : .init(status: 503)
        }
        let waiting = NodSession(client: client, retryBase: 5, retryCap: 5)
        waiting.start()
        try await eventually { stateGETs() >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        check(stateGETs() == 1, "retry waits for its backoff instead of hammering Nod")
        healthy.withLock { $0 = true }
        ClientStub.emit("data: {\"type\":\"refresh\"}\n\n")
        try await eventually { waiting.store.state == .rest }
        check(true, "a new event during the backoff fetches immediately")
        waiting.disconnect()

        // Persistent failure keeps trying at a bounded rate; disconnect stops it.
        ClientStub.configure { request in
            request.url?.path == "/api/events" ? .init(mime: "text/event-stream", finish: false) : .init(status: 401)
        }
        let rejected = NodSession(client: client, retryBase: 0.05, retryCap: 0.05)
        rejected.start()
        try await Task.sleep(for: .milliseconds(400))
        let attempts = stateGETs()
        check(attempts >= 3 && attempts <= 10, "401 is retried only at the capped backoff rate (\(attempts) GETs in 400 ms)")
        rejected.disconnect()
        let stopped = stateGETs()
        try await Task.sleep(for: .milliseconds(150))
        check(stateGETs() == stopped, "disconnect cancels a pending retry")
    }
}
