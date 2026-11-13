import Foundation

/// Markdown as one line of plain text, for the narrow wing next to the camera housing.
///
/// Removed: `#` headings, `>` quotes, list markers, code fences, rules, table pipes and separator rows, `**`/`__`
/// bold, `*`/`_` italics, `~~` strikethrough, backticks, and links (`[text](url)` becomes `text`, images their alt).
/// Line breaks and runs of spaces become one space.
///
/// Limits, on purpose, so plain prose survives:
/// - `_` and `*` count as emphasis only when they hug the text on both sides and are not inside a word. So
///   `snake_case` and `2 * 3 * 4` stay as written, and so does `2*3*4`; `un*frigging*believable` does too.
/// - An emphasis marker that opens like `*a` but closes like `b *` (space before the closing one) stays as written.
/// - Backslash escapes are not read: `\*` keeps its backslash. Nested emphasis beyond `***x***` is not handled.
/// - Code spans use single backticks; their content is kept verbatim. HTML and reference-style links are not handled.
public enum MarkdownPlain {
    public static func line(_ text: String) -> String {
        var pieces: [String] = []
        var inFence = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = MarkdownLineState.trimmed(raw)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { pieces.append(String(line)); continue }
            if line.isEmpty || MarkdownLineState.isRule(line) || MarkdownLineState.isTableSeparator(line) { continue }

            while line.hasPrefix(">") { line = MarkdownLineState.trimmed(line.dropFirst()) }
            if let level = MarkdownLineState.headingLevel(line) {
                line = MarkdownLineState.trimmed(line.dropFirst(level))
            } else if let item = MarkdownLineState.bullet(line) ?? MarkdownLineState.numbered(line) {
                line = MarkdownLineState.trimmed(item)
            } else if line.hasPrefix("|") {
                line = Substring(MarkdownLineState.cells(line).joined(separator: " "))
            }
            pieces.append(inline(String(line)))
        }
        return pieces.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Code spans are set aside first, so what is inside them is never read as emphasis.
    private static func inline(_ text: String) -> String {
        // Private-use scalars stand in for code spans; any that the text itself brings along carry no meaning.
        let base: UInt32 = 0xE000
        var source = String(String.UnicodeScalarView(text.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) }))
        var spans: [String] = []
        source = source.replacingMatches(of: "`([^`]+)`") { groups in
            // Past the last stand-in the span just stays as written, backticks and all.
            guard spans.count <= 0x18FF else { return groups[0] }
            spans.append(groups[1])
            return String(Unicode.Scalar(base + UInt32(spans.count - 1))!)
        }

        // Links and images first, so `*` or `_` inside a link text is still read as emphasis afterwards.
        source = source.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)\s]*(?:\s+"[^"]*")?\)"#, with: "$1", options: .regularExpression)
        let word = #"\p{L}\p{N}"#
        let rules = [
            #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#,
            #"(?<![\#(word)_])__(?=\S)(.+?)(?<=\S)__(?![\#(word)_])"#,
            #"~~(?=\S)(.+?)(?<=\S)~~"#,
            #"(?<![\#(word)*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\#(word)*])"#,
            #"(?<![\#(word)_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\#(word)_])"#,
        ]
        for rule in rules { source = source.replacingOccurrences(of: rule, with: "$1", options: .regularExpression) }

        var result = String.UnicodeScalarView()
        for scalar in source.unicodeScalars {
            if (0xE000...0xF8FF).contains(scalar.value), Int(scalar.value - base) < spans.count {
                result.append(contentsOf: spans[Int(scalar.value - base)].unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}

private extension String {
    /// Replaces every match of `pattern`; `transform` gets the match's groups (0 is the whole match).
    func replacingMatches(of pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }
}
