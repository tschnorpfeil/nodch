import Foundation
import NodchCore

@MainActor func require(_ condition: Bool, _ name: String) throws {
    guard condition else { throw NodClientError.configuration("Contract failed: \(name)") }
    print("PASS \(name)")
}

@MainActor func run() async throws {
    let configuration = try NodConfiguration.fromEnvironment()
    let anonymous = NodClient(configuration: .init(baseURL: configuration.baseURL))
    do { _ = try await anonymous.state(); throw NodClientError.configuration("Anonymous request succeeded") }
    catch NodClientError.unauthorized { print("PASS without credentials -> 401") }
    let client = NodClient(configuration: configuration)
    _ = try await client.state()
    print("PASS with credentials -> 200")
    let session = NodSession(client: client)
    session.start()
    defer { session.disconnect() }
    // Establish SSE and the initial snapshot before submitting. No manual refresh follows the send.
    let connectedDeadline = Date().addingTimeInterval(10)
    while session.store.state != .rest && Date() < connectedDeadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    try require(session.store.state == .rest, "SSE connects and loads initial state")
    _ = try await client.send(prompt: "Nodch contract: propose pausing proactive notifications and ask for confirmation.")
    print("PASS send prompt -> accepted")
    let deadline = Date().addingTimeInterval(60)
    var pending: PendingApproval?
    while Date() < deadline {
        if case .needsYou(let approval, _) = session.store.state { pending = approval; break }
        try await Task.sleep(for: .milliseconds(50))
    }
    guard let approval = pending else { throw NodClientError.configuration("No approval via SSE + state: \(session.store.state)") }
    print("PASS SSE + state -> IslandState.needsYou")
    try await session.answer(approval: approval, approved: true)
    print("PASS approve -> accepted")
    do { try await session.answer(approval: approval, approved: true); throw NodClientError.configuration("Duplicate approval succeeded") }
    catch NodClientError.conflict { print("PASS duplicate approval -> 409 (no retry)") }
    try await session.stop()
    let settled = Date().addingTimeInterval(20)
    while Date() < settled {
        switch session.store.state {
        case .working, .needsYou: try await Task.sleep(for: .milliseconds(50)); continue
        default: break
        }
        break
    }
    switch session.store.state {
    case .working, .needsYou: throw NodClientError.configuration("Still busy after stop: \(session.store.state)")
    default: print("PASS stop -> accepted, island settles (\(session.store.state))")
    }
    // Last: Nod hands an attached file to its workspace runtime, which this minimal fixture does not provide, so the
    // turn it starts may fail. The contract is only that the upload reaches Nod and the message carries it.
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/contract-upload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("Übersicht – März.txt")
    let contents = "Nodch attachment contract."
    try contents.write(to: file, atomically: true, encoding: .utf8)
    let attachment = try await session.upload(file: file)
    try require(UUID(uuidString: attachment.id) != nil && attachment.name == "Übersicht – März.txt" &&
                attachment.mimeType == "text/plain" && attachment.size == contents.utf8.count,
                "upload text file -> Artifact with id, name, MIME and size")
    let submission = try await client.send(prompt: "", attachments: [attachment])
    print("PASS send attachment without text -> accepted")
    struct Snapshot: Decodable {
        struct Message: Decodable {
            struct Attachment: Decodable { let id: String; let name: String; let mimeType: String; let size: Int }
            let id: String
            let text: String
            let attachments: [Attachment]
        }
        let messages: [Message]
    }
    let (data, response) = try await URLSession.shared.data(for: configuration.request(path: "/api/state"))
    try require((response as? HTTPURLResponse)?.statusCode == 200, "GET state with uploaded attachment -> 200")
    let message = try JSONDecoder().decode(Snapshot.self, from: data).messages.first { $0.id == submission.messageId }
    let stored = message?.attachments.first
    try require(message?.text == "" && stored?.id == attachment.id && stored?.name == attachment.name &&
                stored?.mimeType == attachment.mimeType && stored?.size == attachment.size,
                "GET state -> sent message carries uploaded attachment")
}

do { try await run() }
catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
