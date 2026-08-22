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

nonisolated enum AssistantMarkdown {
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
