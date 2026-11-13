// Adapted from Pippa: app/Sources/PippaChecks/MarkdownChecks.swift
import NodchCore

/// Markdown: the block parser finds every kind of block and leaves look-alikes as text; `MarkdownPlain.line` turns an
/// answer into one plain line for the wing.
@MainActor enum MarkdownChecks {
    static func run() {
        let full = """
        ## Overview
        Your status is **report.md**,
        last changed on 1 November.

        - **World:** 62 %
          - of which plan 400 €
            the rest once
        - **Bonds:** 20 %
        1. Check first
        2. Then transfer

        > Objections within four weeks.

        ```swift
        let total = 184.37

        print(total)
        ```

        | Year | Result |
        |---|---:|
        | 2024 | 90.55 € |
        | 2025 | 184.37 € |

        ---
        # End
        After the table.
        """
        let expected: [MarkdownBlock] = [
            .heading(2, "Overview"),
            .paragraph("Your status is **report.md**,\nlast changed on 1 November."),
            .list([.init(text: "**World:** 62 %", indent: 0),
                   .init(text: "of which plan 400 € the rest once", indent: 1),
                   .init(text: "**Bonds:** 20 %", indent: 0)], ordered: false),
            .list([.init(text: "Check first", indent: 0), .init(text: "Then transfer", indent: 0)], ordered: true),
            .quote("Objections within four weeks."),
            .code("let total = 184.37\n\nprint(total)"),
            .table(["Year", "Result"], [["2024", "90.55 €"], ["2025", "184.37 €"]]),
            .rule,
            .heading(1, "End"),
            .paragraph("After the table."),
        ]
        let blocks = MarkdownBlock.parse(full)
        if blocks != expected { print("  got: \(blocks)") }
        check(blocks == expected, "markdown: a full parse finds every kind of block")

        let lookAlikes = ["2 * 3 = 6", "Version 1.2", "2024. A year", "#hashtag", "-5 degrees", "a | b | c", "1.2 is the version", "**bold** start"]
        check(lookAlikes.allSatisfy { MarkdownBlock.parse($0) == [.paragraph($0)] }, "markdown: lines that only look like blocks stay a paragraph")
        check(MarkdownBlock.parse("| no | head |\nText right after") == [.paragraph("| no | head |\nText right after")],
              "markdown: a pipe line without a separator is not a table")

        let open = MarkdownBlock.parse("Before\n```\nopen to the end\n| no | table |\n# not a heading")
        check(open == [.paragraph("Before"), .code("open to the end\n| no | table |\n# not a heading")], "markdown: an open code fence holds the rest")

        let lists = MarkdownBlock.parse("* Star\n+ Plus\n• Dot\n10) Ten\n***\n\n\n- a\n\n- b")
        check(lists == [.list([.init(text: "Star", indent: 0), .init(text: "Plus", indent: 0), .init(text: "Dot", indent: 0)], ordered: false),
                        .list([.init(text: "Ten", indent: 0)], ordered: true), .rule,
                        .list([.init(text: "a", indent: 0)], ordered: false), .list([.init(text: "b", indent: 0)], ordered: false)],
              "markdown: list markers, ordered and unordered lists, rules")
        check(MarkdownBlock.parse("") == [] && MarkdownBlock.parse("\n\n  \n") == [], "markdown: empty text has no blocks")
        check(MarkdownBlock.parse("a\r\n\r\nb") == [.paragraph("a"), .paragraph("b")], "markdown: CRLF line ends parse like LF")

        let answer = "**Morgen** ist *Samstag*\n\n- `a`\n- [Link](https://x.y)"
        check(MarkdownPlain.line(answer) == "Morgen ist Samstag a Link", "markdown plain: emphasis, code and link markup is gone")
        check(MarkdownPlain.line("snake_case and my_var_name stay, __bold__ and _it_ go") == "snake_case and my_var_name stay, bold and it go",
              "markdown plain: snake_case survives, word-bounded underscores are emphasis")
        check(MarkdownPlain.line("2 * 3 = 6 and 4*5*6") == "2 * 3 = 6 and 4*5*6", "markdown plain: asterisks in sums stay")
        check(MarkdownPlain.line("`a*b*c` and `x_y_z`") == "a*b*c and x_y_z", "markdown plain: code spans keep their content")
        check(MarkdownPlain.line("# Title\n> quoted\n1. one\n2) two\n---\n| a | b |\n|---|---|\n| 1 | 2 |") == "Title quoted one two a b 1 2",
              "markdown plain: headings, quotes, list markers, rules and tables")
        check(MarkdownPlain.line("```swift\nlet x = 2 * 3\n```\nDone") == "let x = 2 * 3 Done", "markdown plain: code fences go, their lines stay untouched")
        check(MarkdownPlain.line("  a \n\n\n  b   c  ") == "a b c" && MarkdownPlain.line("") == "", "markdown plain: whitespace collapses to single spaces")
        check(MarkdownPlain.line("see ![pic](https://x.y/a.png) and [**bold link**](https://x.y \"t\")") == "see pic and bold link",
              "markdown plain: images and links keep their text")
    }
}
