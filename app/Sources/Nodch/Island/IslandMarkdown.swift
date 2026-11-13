// Adapted from Pippa: app/Sources/Pippa/Views/MarkdownText.swift
import NodchCore
import SwiftUI

/// Nod's answer as Markdown, in the island's type: white on the dark card, rounded sans, nothing from Nod's own look.
/// Inline styling (bold, italic, code, links) comes from `AttributedString(markdown:)`; blocks from `MarkdownBlock`.
struct IslandMarkdown: View {
    let text: String

    private static let mono = Font.system(size: 12, design: .monospaced)
    private static let lineSpacing: CGFloat = 2
    private static let indent: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: IslandStyle.gap) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).font(IslandStyle.body)
                .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                .lineSpacing(Self.lineSpacing).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text)).font(level <= 2 ? IslandStyle.title : IslandStyle.body.weight(.semibold))
                .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: ordered ? "\(index + 1)." : "•").monospacedDigit()
                            .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                            .frame(minWidth: ordered ? 18 : 10, alignment: .trailing)
                        Text(Self.inline(item.text))
                            .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                            .lineSpacing(Self.lineSpacing).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(min(item.indent, 4)) * Self.indent)
                }
            }
            .font(IslandStyle.body)
        case .quote(let text):
            Text(Self.inline(text)).font(IslandStyle.body)
                .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                .lineSpacing(Self.lineSpacing).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(IslandStyle.white(IslandStyle.tertiary)).frame(width: 2)
                }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: text).font(Self.mono)
                    .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandStyle.white(0.08), in: RoundedRectangle(cornerRadius: IslandStyle.wellRadius, style: .continuous))
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell)).font(IslandStyle.small.weight(.semibold))
                                .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                        }
                    }
                    Rectangle().fill(IslandStyle.white(0.15)).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(0..<header.count, id: \.self) { column in
                                Text(Self.inline(column < row.count ? row[column] : ""))
                                    .font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                            }
                        }
                    }
                }
            }
        case .rule:
            Rectangle().fill(IslandStyle.white(0.15)).frame(height: 1)
        }
    }

    /// Bold, italic, code and links. Inline code gets a monospaced face on a faint fill; only web and mail links stay
    /// clickable, anything else (file:, custom schemes) is shown as plain text.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in result.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                result[run.range].font = mono
                result[run.range].backgroundColor = IslandStyle.white(0.1)
            }
            if let url = run.link {
                if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    result[run.range].foregroundColor = IslandStyle.accent
                    result[run.range].underlineStyle = .single
                } else {
                    result[run.range].link = nil
                }
            }
        }
        return result
    }
}
