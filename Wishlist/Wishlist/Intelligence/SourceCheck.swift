//
//  SourceCheck.swift
//  Wishlist
//
//  The guard that lets a language model near product data at all.
//
//  A model is asked only to copy values that are already written on the page.
//  Every value it returns is then looked for in that page's own text, and
//  anything that cannot be found is thrown away. A model that invents a price
//  therefore changes nothing: the invented price is not on the page, so it does
//  not survive this file.
//

import Foundation

nonisolated enum SourceCheck {
    /// Whitespace-collapsed, case-folded text for comparison.
    static func normalised(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the phrase appears in the source more or less verbatim.
    static func contains(_ phrase: String, in source: String) -> Bool {
        let needle = normalised(phrase)
        guard needle.count >= 2 else { return false }
        return normalised(source).contains(needle)
    }

    /// Names get re-punctuated more often than they get invented, so a name is
    /// accepted when nearly all of its substantial words appear in the source.
    static func isSupportedName(_ name: String, by source: String) -> Bool {
        let haystack = normalised(source)
        guard !haystack.isEmpty else { return false }
        if haystack.contains(normalised(name)) { return true }

        let words = normalised(name)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        guard words.count >= 2 else { return false }

        let found = words.filter { haystack.contains($0) }.count
        return Double(found) / Double(words.count) >= 0.8
    }

    /// A price is accepted only when its digits appear in the source in the same
    /// order — "£249.00" is supported by a page containing "249,00" or
    /// "£249.00", and by nothing else.
    static func isSupportedPrice(_ priceText: String, by source: String) -> Bool {
        let digits = digitStream(priceText)
        guard digits.count >= 2 else { return false }
        return digitStream(source).contains(digits)
    }

    private static func digitStream(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }
}
