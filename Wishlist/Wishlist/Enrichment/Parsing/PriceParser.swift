//
//  PriceParser.swift
//  Wishlist
//
//  Turns the many ways a retailer writes a price ("£1,299.00", "1.299,00 €",
//  "USD 24.99", "24990") into a `Decimal` plus a currency code — or into
//  nothing at all. Returning `nil` is a perfectly good answer: a price Wishlist
//  is not sure about is worse than no price.
//

import Foundation

nonisolated enum PriceParser {
    /// Symbols that map unambiguously to one currency.
    private static let symbolCurrencies: [(symbol: String, code: String)] = [
        ("R$", "BRL"), ("C$", "CAD"), ("A$", "AUD"), ("NZ$", "NZD"), ("HK$", "HKD"),
        ("S$", "SGD"), ("CHF", "CHF"), ("zł", "PLN"), ("Kč", "CZK"),
        ("£", "GBP"), ("€", "EUR"), ("¥", "JPY"), ("₹", "INR"), ("₩", "KRW"),
        ("₽", "RUB"), ("₺", "TRY"), ("₪", "ILS"), ("฿", "THB"), ("₱", "PHP"),
        ("₫", "VND"), ("₦", "NGN"), ("﷼", "SAR")
    ]

    /// Three-letter codes we accept when they appear as a standalone token.
    private static let knownCodes: Set<String> = [
        "USD", "GBP", "EUR", "JPY", "CAD", "AUD", "NZD", "CHF", "SEK", "NOK",
        "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "TRY", "INR", "SGD", "HKD",
        "CNY", "KRW", "BRL", "MXN", "ARS", "CLP", "ZAR", "AED", "SAR", "EGP",
        "ILS", "THB", "PHP", "MYR", "IDR", "VND", "RUB", "UAH", "NGN"
    ]

    /// Extracts an amount and, when it is stated, a currency.
    ///
    /// - Parameters:
    ///   - text: the raw price string from a page or API.
    ///   - currencyHint: a currency the caller already knows (e.g. declared by
    ///     JSON-LD or implied by an Amazon marketplace). Used only when the
    ///     text itself does not state one.
    static func parse(_ text: String?, currencyHint: String? = nil) -> Money? {
        guard let text, !text.isEmpty else { return nil }
        guard let amount = decimal(fromNumericString: text) else { return nil }
        guard amount > 0 else { return nil }
        let currency = currency(in: text) ?? currencyHint
        return Money(amount: amount, currencyCode: currency)
    }

    /// Finds a currency stated inside a price string, if any.
    static func currency(in text: String) -> String? {
        let upper = text.uppercased()
        for candidate in knownCodes where containsToken(candidate, in: upper) {
            return candidate
        }
        for entry in symbolCurrencies where text.contains(entry.symbol) {
            return entry.code
        }
        return nil
    }

    /// True when `token` appears in `text` bounded by non-letters, so "USD" in
    /// "USD 24.99" matches but the "EUR" inside "EUROPEAN" does not.
    private static func containsToken(_ token: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: token, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == text.endIndex
                || !text[range.upperBound].isLetter
            if beforeOK && afterOK { return true }
            guard range.upperBound < text.endIndex else { return false }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    /// Pulls the most plausible number out of a string, working out for
    /// itself whether "." and "," are grouping or decimal separators.
    static func decimal(fromNumericString text: String) -> Decimal? {
        guard let slice = bestNumericSlice(in: text) else { return nil }
        let normalised = normaliseSeparators(slice)
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Every run of digits (optionally interrupted by "." or ","), paired with
    /// where it started. Percentages are skipped so "Save 20% — £24.99" reads
    /// as 24.99 rather than 20.
    private static func numericSlices(in text: String) -> [(value: String, offset: Int)] {
        var slices: [(value: String, offset: Int)] = []
        var current = ""
        var currentStart = 0
        let characters = Array(text)

        func flush(endingAt index: Int) {
            while let last = current.last, last == "." || last == "," {
                current.removeLast()
            }
            guard !current.isEmpty else { current = ""; return }
            let isPercentage = index < characters.count && characters[index] == "%"
            if !isPercentage { slices.append((current, currentStart)) }
            current = ""
        }

        for (index, character) in characters.enumerated() {
            if character.isNumber {
                if current.isEmpty { currentStart = index }
                current.append(character)
            } else if !current.isEmpty, character == "." || character == "," {
                current.append(character)
            } else if !current.isEmpty {
                flush(endingAt: index)
            }
        }
        flush(endingAt: characters.count)
        return slices
    }

    /// When the string states a currency, the number nearest to it is the
    /// price; otherwise the first number is the best available guess.
    private static func bestNumericSlice(in text: String) -> String? {
        let slices = numericSlices(in: text)
        guard !slices.isEmpty else { return nil }
        guard let anchor = currencyAnchor(in: text) else { return slices[0].value }
        return slices.min { lhs, rhs in
            abs(lhs.offset - anchor) < abs(rhs.offset - anchor)
        }?.value ?? slices[0].value
    }

    /// Character offset of the currency symbol or code inside the string.
    private static func currencyAnchor(in text: String) -> Int? {
        let characters = Array(text)
        let upper = text.uppercased()
        var candidates: [String] = symbolCurrencies.map { $0.symbol }
        candidates.append(contentsOf: knownCodes)
        for candidate in candidates {
            if let range = upper.range(of: candidate.uppercased()) {
                let offset = upper.distance(from: upper.startIndex, to: range.lowerBound)
                if offset <= characters.count { return offset }
            }
        }
        return nil
    }

    /// Reduces a mixed-separator number to a plain "1234.56".
    private static func normaliseSeparators(_ text: String) -> String {
        let hasDot = text.contains(".")
        let hasComma = text.contains(",")

        if hasDot && hasComma {
            // Whichever appears last is the decimal separator.
            let lastDot = text.lastIndex(of: ".")
            let lastComma = text.lastIndex(of: ",")
            let decimalSeparator: Character = (lastDot! > lastComma!) ? "." : ","
            let grouping: Character = decimalSeparator == "." ? "," : "."
            return text
                .replacingOccurrences(of: String(grouping), with: "")
                .replacingOccurrences(of: String(decimalSeparator), with: ".")
        }

        let separator: Character? = hasDot ? "." : (hasComma ? "," : nil)
        guard let separator else { return text }

        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        // "1,234,567" — repeated separators can only be grouping.
        guard parts.count == 2 else {
            return text.replacingOccurrences(of: String(separator), with: "")
        }
        // A trailing group of exactly three digits is ambiguous ("1,234"), and
        // grouping is overwhelmingly the more common meaning.
        let fraction = parts[1]
        if fraction.count == 3 {
            return text.replacingOccurrences(of: String(separator), with: "")
        }
        return String(parts[0]) + "." + String(fraction)
    }
}
