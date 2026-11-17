import Foundation
import NodchCore

extension ClientChecks {
    /// Stop reaches Nod once, on the route its scope names: `POST /api/tasks/:id/stop` for a task (Nod 915e4f1
    /// src/server/tasks.ts), `POST /api/thread/stop` for all work (src/server/app.ts). A failed task stop is never
    /// repeated or widened.
    static func stopChecks() async throws {
        let task = "00000000-0000-4000-8000-00000000D0C1"
        // The mapper carries the displayed activity's taskId; a running turn without activity has none.
        var mapper = NodStateMapper()
        let tasked = String(decoding: fixture(status: "running", activity: true), as: UTF8.self)
            .replacingOccurrences(of: "\"taskId\":null", with: "\"taskId\":\"\(task)\"")
        if case .working(let work) = mapper.map(try .decode(Data(tasked.utf8))) {
            check(work.taskID == task && work.stopScope == .task(task), "stop: the mapper keeps the displayed activity's taskId")
        } else { check(false, "stop: the mapper keeps the displayed activity's taskId") }
        if case .working(let work) = mapper.map(try .decode(fixture(status: "running"))) {
            check(work.stopScope == .thread, "stop: a running turn without activity stops all work")
        } else { check(false, "stop: a running turn without activity stops all work") }
        if case .working(let work) = mapper.map(try .decode(fixture(status: "running", activity: true))) {
            check(work.stopScope == .thread, "stop: an activity with taskId null stops all work")
        } else { check(false, "stop: an activity with taskId null stops all work") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = NodClient(configuration: .init(credential: .bearer("fixture")), session: transport)
        let posts = { ClientStub.requests.filter { $0.httpMethod == "POST" }.compactMap { $0.url?.path } }

        ClientStub.configure { _ in .init(body: Data("{\"ok\":true}".utf8)) }
        try await client.stop(.task(task))
        check(posts() == ["/api/tasks/\(task.lowercased())/stop"], "stop: a task stop posts once to its own route")
        ClientStub.configure { _ in .init(body: Data("{\"ok\":true}".utf8)) }
        try await client.stop(.thread)
        check(posts() == ["/api/thread/stop"], "stop: Stop all work posts once to the thread route")

        let idle = fixture()
        for status in [404, 500, 409] {
            ClientStub.configure { request in
                request.httpMethod == "POST" ? .init(status: status, body: Data("{\"error\":\"Task not found.\"}".utf8)) : .init(body: idle)
            }
            let session = NodSession(client: client)
            do { try await session.stop(.task(task)); check(false, "stop: HTTP \(status) on a task stop throws") }
            catch { check(error is NodClientError, "stop: HTTP \(status) on a task stop throws") }
            check(posts() == ["/api/tasks/\(task.lowercased())/stop"], "stop: HTTP \(status) on a task stop is not retried or widened to all work")
            session.disconnect()
        }
        ClientStub.configure { _ in .init(body: Data("{\"ok\":true}".utf8)) }
        do { try await client.stop(.task("../thread")); check(false, "stop: a task id that is not a UUID is refused") }
        catch NodClientError.invalidInput { check(posts().isEmpty, "stop: a task id that is not a UUID sends nothing") }
    }
}
