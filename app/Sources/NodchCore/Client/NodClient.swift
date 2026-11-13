import Foundation
import UniformTypeIdentifiers

public enum NodClientError: Error, LocalizedError, Equatable, Sendable {
    case configuration(String)
    case credentials
    case unauthorized
    case conflict(String)
    case http(Int, String)
    case network(String)
    case invalidResponse
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .configuration(let reason): reason
        case .credentials: "Check Nod credentials: set NOD_AUTH_TOKEN or NOD_DATA_ROOT to Nod's access-key directory."
        case .unauthorized: "Nod rejected the credentials. Check NOD_AUTH_TOKEN or Nod's access-key file."
        case .conflict(let reason): "This action is no longer available. Review Nod's current state. \(reason)"
        case .http(let status, let reason): "Nod returned HTTP \(status). \(reason)"
        case .network(let reason): "Cannot reach Nod. \(reason)"
        case .invalidResponse: "Nod returned an invalid response."
        case .invalidInput(let reason): reason
        }
    }
}

public struct NodSubmission: Decodable, Sendable {
    public let threadId: String
    public let turnId: String
    public let messageId: String
}

public enum NodEvent: Sendable {
    case connected
    case update(String)
}

/// HTTP mutations are deliberately sent once, without application-level retries.
public final class NodClient: Sendable {
    public let configuration: NodConfiguration
    private let session: URLSession

    public init(configuration: NodConfiguration, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.configuration = configuration
        self.session = session
    }

    public func state() async throws -> NodState {
        let data = try await perform(configuration.request(path: "/api/state"))
        do { return try NodState.decode(data) }
        catch { throw NodClientError.invalidResponse }
    }

    public func send(prompt: String, attachments: [NodAttachment] = []) async throws -> NodSubmission {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            throw NodClientError.invalidInput("Write a message or attach a file before sending.")
        }
        return try await submit(MessageInput(text: prompt, clientMessageId: UUID().uuidString.lowercased(),
                                             attachmentIds: attachments.map(\.id)))
    }

    public func upload(file dropped: URL) async throws -> NodAttachment {
        guard dropped.isFileURL else { throw NodClientError.invalidInput("Choose a local file to upload.") }
        // A symlink uploads the file it points to, under the name the person dropped.
        let file = dropped.resolvingSymlinksInPath()
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        // Nod 915e4f1: src/shared/files.ts and src/server/artifacts.ts.
        let limit = 90 * 1024 * 1024
        let sizeError = NodClientError.invalidInput("Choose a file between 1 byte and 90 MiB to upload.")
        let bytes: Data
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw NodClientError.invalidInput("Choose a file to upload; folders and packages are not supported.")
            }
            guard let size = values.fileSize, size > 0, size <= limit else { throw sizeError }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            // Bound the read as well, in case the file grows after the size check. The whole file is held in memory
            // (about twice, with the multipart body): fine for Nod's 90 MiB cap.
            bytes = try handle.read(upToCount: limit + 1) ?? Data()
            guard !bytes.isEmpty, bytes.count <= limit else { throw sizeError }
        } catch let error as NodClientError { throw error }
        catch { throw NodClientError.invalidInput("Cannot read the selected file. \(error.localizedDescription)") }

        let boundary = "nodch-\(UUID().uuidString)"
        // Nod's multipart parser does not percent-decode, so only what would break the header is escaped, as browsers
        // do; a backslash would read as a path separator there.
        let name = dropped.lastPathComponent
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = try configuration.request(path: "/api/uploads", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await perform(request)
        struct Artifact: Decodable { let id: String; let name: String; let mimeType: String; let size: Int }
        do {
            let artifact = try JSONDecoder().decode(Artifact.self, from: data)
            return NodAttachment(id: artifact.id, name: artifact.name, mimeType: artifact.mimeType, size: artifact.size)
        } catch { throw NodClientError.invalidResponse }
    }

    public func answer(approval: PendingApproval, approved: Bool) async throws -> NodSubmission {
        try await submit(MessageInput(text: approved ? "Yes" : "No", clientMessageId: UUID().uuidString.lowercased(),
                                      replyToMessageId: approval.messageID,
                                      approvalAnswer: .init(approvalId: approval.id, approved: approved)))
    }

    /// Answers Nod's open question as Nod's web app does (src/web/components/answer-choices.tsx `answer()`): the picked
    /// labels in question order, then the person's trimmed words on the next line. Nod 915e4f1 src/server/thread.ts
    /// checks that text against `choiceAnswerText`, and allows one pick without own words unless the question is multiple.
    public func answer(question: NodAnswer, choices: [NodQuestion.Choice], text: String) async throws -> NodSubmission {
        guard let open = question.question else {
            throw NodClientError.invalidInput("This message no longer waits for an answer.")
        }
        let picked = Set(choices.map(\.id))
        let chosen = open.choices.filter { picked.contains($0.id) }
        guard chosen.count == picked.count else { throw NodClientError.invalidInput("Choose one of Nod's answers.") }
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty || !written.isEmpty else {
            throw NodClientError.invalidInput("Pick an answer or write your own before sending.")
        }
        guard open.multiple || (chosen.count <= 1 && (chosen.isEmpty || written.isEmpty)) else {
            throw NodClientError.invalidInput("Pick one answer, or write your own instead.")
        }
        let value = [chosen.isEmpty ? "" : Self.choiceAnswerText(chosen), written].filter { !$0.isEmpty }.joined(separator: "\n")
        let ids = chosen.map(\.id)
        let selection = chosen.isEmpty ? MessageInput.QuestionAnswer(custom: true)
            : MessageInput.QuestionAnswer(choiceIds: ids, custom: written.isEmpty ? nil : true)
        return try await submit(MessageInput(text: value, clientMessageId: UUID().uuidString.lowercased(),
                                             replyToMessageId: question.id, questionAnswer: selection))
    }

    /// Nod 915e4f1 src/shared/answer-choices.ts `choiceAnswerText`.
    static func choiceAnswerText(_ choices: [NodQuestion.Choice]) -> String {
        choices.map { choice in
            let label = choice.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = choice.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !detail.isEmpty && detail.lowercased() != label.lowercased() ? "\(label): \(detail)" : label
        }.joined(separator: "\n")
    }

    public func stop() async throws {
        var request = try configuration.request(path: "/api/thread/stop", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await perform(request)
    }

    public func events() -> AsyncThrowingStream<NodEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try configuration.request(path: "/api/events")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 60
                    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectPolicy.shared)
                    try Self.validate(response, data: Data())
                    guard (response as? HTTPURLResponse)?.mimeType == "text/event-stream" else {
                        throw NodClientError.invalidResponse
                    }
                    continuation.yield(.connected)
                    var parser = SSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for event in parser.append(Data([byte])) {
                            struct Payload: Decodable { let type: String }
                            let type = (try? JSONDecoder().decode(Payload.self, from: Data(event.data.utf8)))?.type ?? event.event
                            continuation.yield(.update(type))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.translate(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct MessageInput: Encodable {
        struct Answer: Encodable { let approvalId: String; let approved: Bool }
        /// Nod's `questionAnswer`: `{choiceIds}`, `{choiceIds, custom: true}` or `{custom: true}`; nil keys are omitted.
        struct QuestionAnswer: Encodable { var choiceIds: [String]? = nil; var custom: Bool? = nil }
        let text: String
        let clientMessageId: String
        var attachmentIds: [String] = []
        var replyToMessageId: String? = nil
        var approvalAnswer: Answer? = nil
        var questionAnswer: QuestionAnswer? = nil
    }

    private func submit(_ input: MessageInput) async throws -> NodSubmission {
        var request = try configuration.request(path: "/api/messages", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)
        let data = try await perform(request)
        do { return try JSONDecoder().decode(NodSubmission.self, from: data) }
        catch { throw NodClientError.invalidResponse }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request, delegate: RedirectPolicy.shared)
            try Self.validate(response, data: data)
            return data
        } catch { throw Self.translate(error) }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw NodClientError.invalidResponse }
        struct Failure: Decodable { let error: String }
        let reason = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? ""
        switch response.statusCode {
        case 200..<300: return
        case 401: throw NodClientError.unauthorized
        case 409: throw NodClientError.conflict(reason)
        default: throw NodClientError.http(response.statusCode, reason)
        }
    }

    private static func translate(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
        if let error = error as? NodClientError { return error }
        return NodClientError.network(error.localizedDescription)
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectPolicy()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
