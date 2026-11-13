// Adapted from Pippa: app/Sources/PippaCore/Markdown/MarkdownBlock.swift
import Foundation

/// An answer's Markdown as blocks: paragraphs, headings, lists, quotes, code, tables and rules. Small models write all
/// of these. Inline styling (bold, code spans, links) stays inside each block's text; the view styles it.
///
/// This is a line-based reader for what chat models write, not CommonMark: no nested quotes or lists inside quotes,
/// no setext headings, no HTML. A line that only looks like markup stays text ("2 * 3 = 6", "Version 1.2"), and an
/// open code fence holds the rest of the text.
public enum MarkdownBlock: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var text: String
        public var indent: Int
        public init(text: String, indent: Int) { self.text = text; self.indent = indent }
    }

    case paragraph(String)
    case heading(Int, String)
    case list([Item], ordered: Bool)
    case quote(String)
    case code(String)
    case table([String], [[String]])
    case rule

    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var state = MarkdownLineState()
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            index += state.take(lines[index], next: next, into: &blocks) ? 2 : 1
        }
        state.finish(into: &blocks)
        return blocks
    }
}

/// What the parser carries from one line to the next: the paragraph or list being collected, or an open code fence or
/// table. Lines go in one at a time; a block leaves through `take` as soon as a line ends it.
struct MarkdownLineState: Sendable {
    private enum Mode: Sendable {
        case text
        case code([String])
        case table([String], [[String]])
    }

    private var mode = Mode.text
    private var paragraph: [String] = []
    private var items: [MarkdownBlock.Item] = []
    private var ordered = false

    /// Takes one line; `next` is the line after it, if there is one. Returns true when `next` was used up too
    /// (the separator under a table head).
    mutating func take(_ raw: Substring, next: Substring?, into blocks: inout [MarkdownBlock]) -> Bool {
        let line = Self.trimmed(raw)
        switch mode {
        case .code(var code):
            if line.hasPrefix("```") {
                blocks.append(.code(code.joined(separator: "\n")))
                mode = .text
            } else {
                code.append(String(raw))
                mode = .code(code)
            }
            return false
        case .table(let header, var rows):
            if line.hasPrefix("|") {
                rows.append(Self.cells(line))
                mode = .table(header, rows)
                return false
            }
            blocks.append(.table(header, rows))
            mode = .text
        case .text:
            break
        }

        let indent = raw.prefix { $0 == " " || $0 == "\t" }.count / 2
        if line.isEmpty { flush(into: &blocks); return false }
        if line.hasPrefix("```") {
            flush(into: &blocks)
            mode = .code([])
            return false
        }
        if let level = Self.headingLevel(line) {
            flush(into: &blocks)
            blocks.append(.heading(level, String(Self.trimmed(line.drop { $0 == "#" }))))
            return false
        }
        if Self.isRule(line) {
            flush(into: &blocks)
            blocks.append(.rule)
            return false
        }
        if line.hasPrefix("|"), let next, Self.isTableSeparator(next) {
            flush(into: &blocks)
            mode = .table(Self.cells(line), [])
            return true
        }
        if line.hasPrefix(">") {
            flush(into: &blocks)
            blocks.append(.quote(String(Self.trimmed(line.dropFirst()))))
            return false
        }
        if let item = Self.bullet(line) {
            if !paragraph.isEmpty || (!items.isEmpty && ordered) { flush(into: &blocks) }
            ordered = false
            items.append(.init(text: String(item), indent: indent))
            return false
        }
        if let item = Self.numbered(line) {
            if !paragraph.isEmpty || (!items.isEmpty && !ordered) { flush(into: &blocks) }
            ordered = true
            items.append(.init(text: String(item), indent: indent))
            return false
        }
        // A line right after a list item continues it.
        if !items.isEmpty, indent > 0 {
            items[items.count - 1].text += " " + line
            return false
        }
        if !items.isEmpty { flush(into: &blocks) }
        paragraph.append(String(line))
        return false
    }

    /// The end of the text: whatever is still open becomes a block.
    mutating func finish(into blocks: inout [MarkdownBlock]) {
        switch mode {
        case .code(let code): blocks.append(.code(code.joined(separator: "\n")))
        case .table(let header, let rows): blocks.append(.table(header, rows))
        case .text: flush(into: &blocks)
        }
        mode = .text
    }

    private mutating func flush(into blocks: inout [MarkdownBlock]) {
        if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        if !items.isEmpty { blocks.append(.list(items, ordered: ordered)); items = [] }
    }

    /// Spaces and tabs off both ends, without copying the line.
    static func trimmed(_ line: Substring) -> Substring {
        func blank(_ character: Character) -> Bool { character.isWhitespace && !character.isNewline }
        guard let first = line.firstIndex(where: { !blank($0) }), let last = line.lastIndex(where: { !blank($0) }) else {
            return line[line.endIndex...]
        }
        return line[first...last]
    }

    static func headingLevel(_ line: Substring) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func isRule(_ line: Substring) -> Bool { line == "---" || line == "***" || line == "___" }

    static func bullet(_ line: Substring) -> Substring? {
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) { return line.dropFirst(marker.count) }
        return nil
    }

    static func numbered(_ line: Substring) -> Substring? {
        let digits = line.prefix(4).prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return rest.dropFirst(2)
    }

    static func isTableSeparator(_ line: Substring) -> Bool {
        let trimmed = Self.trimmed(line)
        return trimmed.hasPrefix("|") && trimmed.contains("-") && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    static func cells(_ line: Substring) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
        if let first = parts.first, trimmed(first).isEmpty { parts.removeFirst() }
        if let last = parts.last, trimmed(last).isEmpty { parts.removeLast() }
        return parts.map { String(trimmed($0)) }
    }
}
