import Foundation
import NodchCore

extension ClientChecks {
    static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    static func uploadChecks() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/upload-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = NodClient(configuration: .init(credential: .bearer("fixture")), session: transport)
        let session = NodSession(client: client)
        defer { session.disconnect() }
        let id = "00000000-0000-4000-8000-000000000005"
        let artifact = Data("{\"id\":\"\(id)\",\"name\":\"server.txt\",\"mimeType\":\"text/plain\",\"size\":5,\"url\":\"/api/artifacts/\(id)\"}".utf8)
        let submission = Data("{\"threadId\":\"thread\",\"turnId\":\"turn\",\"messageId\":\"message\"}".utf8)
        let text = directory.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: text)
        ClientStub.configure { _ in .init(body: artifact) }
        let uploaded = try await session.upload(file: text)
        check(uploaded == NodAttachment(id: id, name: "server.txt", mimeType: "text/plain", size: 5), "Artifact JSON maps to NodAttachment, including server filename")
        let request = ClientStub.requests[0]
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let expected = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--\(boundary)--\r\n"
        check(contentType.hasPrefix("multipart/form-data; boundary=") && !boundary.isEmpty && requestBody(request) == Data(expected.utf8), "upload multipart uses matching boundary, file field, filename, UTType MIME and CRLF framing")
        check(request.httpMethod == "POST" && request.url?.path == "/api/uploads" && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" && ClientStub.requests.count == 1, "upload uses standard bearer auth and one POST")

        // Nod does not percent-decode the multipart filename: "%" goes as is; a quote must not end the header value.
        let odd = directory.appendingPathComponent("100% \"final\".txt")
        try Data("hello".utf8).write(to: odd)
        ClientStub.configure { _ in .init(body: artifact) }
        _ = try await client.upload(file: odd)
        check(requestBody(ClientStub.requests[0]).range(of: Data("filename=\"100% %22final%22.txt\"".utf8)) != nil, "upload filename keeps % and escapes quotes")

        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: text)
        ClientStub.configure { _ in .init(body: artifact) }
        _ = try await client.upload(file: link)
        let linkBody = requestBody(ClientStub.requests[0])
        check(linkBody.range(of: Data("filename=\"link.txt\"".utf8)) != nil && linkBody.range(of: Data("\r\n\r\nhello\r\n".utf8)) != nil, "a symlink uploads its target under the dropped name")

        let unknown = directory.appendingPathComponent("binary.nodch-unknown-extension")
        let binary = Data([0, 255, 13, 10, 42])
        try binary.write(to: unknown)
        ClientStub.configure { _ in .init(body: artifact) }
        _ = try await client.upload(file: unknown)
        let unknownBody = requestBody(ClientStub.requests[0])
        check(unknownBody.range(of: Data("Content-Type: application/octet-stream\r\n\r\n".utf8)) != nil && unknownBody.range(of: binary) != nil, "unknown extension falls back to octet-stream and preserves binary bytes")

        let key = String(repeating: "a", count: 43)
        let keyFile = directory.appendingPathComponent("access-key")
        try key.write(to: keyFile, atomically: true, encoding: .utf8)
        let cookieClient = NodClient(configuration: .init(credential: .accessKeyFile(keyFile)), session: transport)
        ClientStub.configure { _ in .init(body: artifact) }
        _ = try await cookieClient.upload(file: text)
        check(ClientStub.requests[0].value(forHTTPHeaderField: "Cookie") == "nod-access-4310=\(key)" && ClientStub.requests[0].value(forHTTPHeaderField: "Authorization") == nil, "upload uses standard access-key cookie auth")

        // Session forwarding is exercised with both text and attachment-only messages.
        let idle = fixture()
        ClientStub.configure { request in .init(body: request.httpMethod == "POST" ? submission : idle) }
        let second = NodAttachment(id: "00000000-0000-4000-8000-000000000006", name: "other", mimeType: "text/plain", size: 1)
        try await session.send(prompt: "with files", attachments: [uploaded, second])
        try await eventually { ClientStub.requests.contains { $0.url?.path == "/api/state" } }
        try await session.refresh()
        let sendRequest = ClientStub.requests.first { $0.httpMethod == "POST" }!
        let json = try JSONSerialization.jsonObject(with: requestBody(sendRequest)) as! [String: Any]
        check(sendRequest.url?.path == "/api/messages" && json["text"] as? String == "with files" && json["attachmentIds"] as? [String] == [id, second.id], "session send forwards text and attachmentIds in order")
        let sentID = json["clientMessageId"] as? String ?? ""
        check(UUID(uuidString: sentID) != nil && sentID == sentID.lowercased(), "send uses a lowercase client message ID")
        _ = try await client.send(prompt: "", attachments: [uploaded])
        let attachmentOnly = try JSONSerialization.jsonObject(with: requestBody(ClientStub.requests.last!)) as! [String: Any]
        check(attachmentOnly["text"] as? String == "" && attachmentOnly["attachmentIds"] as? [String] == [id], "attachment-only message is sent with empty text")

        ClientStub.configure { _ in .init(status: 500) }
        do { _ = try await client.send(prompt: " \n", attachments: []); check(false, "empty message rejected") }
        catch NodClientError.invalidInput(let reason) { check(!reason.isEmpty && ClientStub.requests.isEmpty, "blank text without attachments is rejected before any request") }
        do { _ = try await session.upload(file: directory); check(false, "directory rejected") }
        catch NodClientError.invalidInput(let reason) { check(reason.contains("folders") && ClientStub.requests.isEmpty, "directory URL is rejected before any request") }
        let oversized = directory.appendingPathComponent("large.txt")
        FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 90 * 1024 * 1024 + 1)
        try handle.close()
        do { _ = try await session.upload(file: oversized); check(false, "oversize rejected") }
        catch NodClientError.invalidInput(let reason) { check(reason.contains("90 MiB") && ClientStub.requests.isEmpty, "oversize file is rejected before any request") }
        let empty = directory.appendingPathComponent("empty.txt")
        try Data().write(to: empty)
        do { _ = try await client.upload(file: empty); check(false, "empty file rejected") }
        catch NodClientError.invalidInput { check(ClientStub.requests.isEmpty, "zero-byte file is rejected before any request") }
        do { _ = try await client.upload(file: directory.appendingPathComponent("missing")); check(false, "unreadable file rejected") }
        catch NodClientError.invalidInput(let reason) { check(reason.contains("Cannot read") && ClientStub.requests.isEmpty, "unreadable file reports a local error without a request") }

        ClientStub.configure { _ in .init(status: 413, body: Data("{\"error\":\"File is too large.\"}".utf8)) }
        do { _ = try await session.upload(file: text); check(false, "upload HTTP error") }
        catch let error as NodClientError {
            check(error == .http(413, "File is too large.") && error.localizedDescription.contains("File is too large.") && ClientStub.requests.count == 1, "non-2xx upload is readable and never retried")
        }
        ClientStub.configure { _ in .init(error: URLError(.networkConnectionLost)) }
        do { _ = try await session.upload(file: text); check(false, "upload network error") }
        catch NodClientError.network { check(ClientStub.requests.count == 1, "upload network failure is never retried") }
        ClientStub.configure { _ in .init(body: Data("{}".utf8)) }
        do { _ = try await client.upload(file: text); check(false, "invalid Artifact") }
        catch NodClientError.invalidResponse { check(true, "invalid Artifact JSON has a typed error") }
    }
}
