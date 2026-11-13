import Foundation

public struct SSEEvent: Equatable, Sendable {
    public var event: String
    public var data: String
    public var id: String?
}

/// Incremental UTF-8 parsing. CR, LF and CRLF are accepted, even across chunks.
/// An incomplete event is discarded when the connection closes, per SSE framing.
public struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var skipLF = false
    private var firstLine = true
    private var event = "message"
    private var data: [String] = []
    private var id: String?

    public init() {}

    public mutating func append(_ chunk: Data) -> [SSEEvent] {
        var result: [SSEEvent] = []
        for byte in chunk {
            if skipLF { skipLF = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                var text = String(decoding: line, as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                if firstLine { firstLine = false; if text.hasPrefix("\u{FEFF}") { text.removeFirst() } }
                if let item = consume(text) { result.append(item) }
                skipLF = byte == 13
            } else { line.append(byte) }
        }
        return result
    }

    private mutating func consume(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = "message"; data.removeAll(keepingCapacity: true) }
            guard !data.isEmpty else { return nil }
            return SSEEvent(event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"), id: id)
        }
        guard !line.hasPrefix(":") else { return nil }
        let split = line.firstIndex(of: ":")
        let field = split.map { String(line[..<$0]) } ?? line
        var value = split.map { String(line[line.index(after: $0)...]) } ?? ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "data": data.append(value)
        case "event": event = value
        case "id": if !value.contains("\0") { id = value }
        default: break
        }
        return nil
    }
}
