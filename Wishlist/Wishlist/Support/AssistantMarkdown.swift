//
//  AssistantMarkdown.swift
//  Wishlist
//
//  Language models write markdown whether or not you ask them to. SwiftUI only
//  parses markdown in string *literals*, so a reply held in a variable arrives
//  on screen with its asterisks showing.
//
//  This parses the inline syntax that actually matters in a chat bubble — bold,
//  italic, code, links — while preserving line breaks, and turns the block
//  syntax that has no place in a bubble into something readable rather than
//  literal punctuation.
//

import Foundation

/// A table lifted out of a reply, so it can be laid out as one rather than
/// shown as a row of pipes.
nonisolated struct AssistantTable: Hashable, Sendable {
    var header: [String]
    var rows: [[String]]

    var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }
}

/// A reply is a sequence of these. Prose is the overwhelming majority; a table
/// is the one block-level construct worth laying out properly.
nonisolated enum AssistantBlock: Hashable, Sendable {
    case prose(String)
    case table(AssistantTable)
}

nonisolated enum AssistantMarkdown {
    /// Splits a reply into prose and tables. Markdown tables cannot be
    /// expressed in an `AttributedString`, so they are pulled out here and
    /// given a real grid to live in.
    static func blocks(in text: String) -> [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        var prose: [String] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.prose(joined)) }
            prose.removeAll()
        }

        while index < lines.count {
            // A table is a row of cells followed by a dashed separator row.
            // Without that separator it is just a sentence containing a pipe.
            if isRow(lines[index]),
               index + 1 < lines.count,
               isSeparator(lines[index + 1]) {
                flushProse()

                let header = cells(in: lines[index])
                index += 2

                var rows: [[String]] = []
                while index < lines.count, isRow(lines[index]) {
                    rows.append(cells(in: lines[index]))
                    index += 1
                }
                blocks.append(.table(AssistantTable(header: header, rows: rows)))
                continue
            }

            prose.append(lines[index])
            index += 1
        }

        flushProse()
        return blocks
    }

    private static func isRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// "|---|:--:|" and friends — dashes, colons and pipes only.
    private static func isSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
    }

    private static func cells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func formatted(_ text: String) -> AttributedString {
        let tidied = tidied(text)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            // Full markdown collapses newlines into paragraphs, which loses the
            // shape of a list. This keeps the line breaks the model intended.
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: tidied, options: options) {
            return parsed
        }
        return AttributedString(tidied)
    }

    /// The same text with its markup resolved away, for VoiceOver — which
    /// would otherwise read "asterisk asterisk" around every bold word.
    static func plain(_ text: String) -> String {
        String(formatted(text).characters)
    }

    /// Rewrites the block-level syntax that inline parsing would otherwise
    /// leave as raw punctuation on screen.
    private static func tidied(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine -> String in
                var line = String(rawLine)

                // A heading inside a chat bubble is just a line of text.
                if line.hasPrefix("#") {
                    line = String(line.drop(while: { $0 == "#" }))
                        .trimmingCharacters(in: .whitespaces)
                }

                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return "• " + trimmed.dropFirst(2)
                }
                return line
            }
            .joined(separator: "\n")
    }
}
