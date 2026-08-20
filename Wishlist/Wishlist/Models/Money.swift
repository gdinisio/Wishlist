//
//  Money.swift
//  Wishlist
//
//  A currency-aware amount. Prices are never stored as strings: the amount is a
//  `Decimal` so arithmetic and comparisons (price drops, totals) stay exact.
//

import Foundation

/// An amount of money, with an optional ISO 4217 currency code.
///
/// The currency is optional on purpose. Some retailers publish a price without
/// declaring a currency, and Wishlist never invents information it did not
/// receive — a price with an unknown currency is shown as a plain number rather
/// than being silently attributed to the user's local currency.
nonisolated struct Money: Hashable, Codable, Sendable {
    var amount: Decimal
    var currencyCode: String?

    init(amount: Decimal, currencyCode: String? = nil) {
        self.amount = amount
        self.currencyCode = currencyCode?.uppercased()
    }

    /// Localised display string, e.g. "£24.99". Falls back to a plain decimal
    /// when the currency is unknown.
    var formatted: String {
        if let currencyCode, !currencyCode.isEmpty {
            return amount.formatted(.currency(code: currencyCode))
        }
        return amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Spoken form for VoiceOver, e.g. "24 pounds 99". `Decimal.formatted`
    /// already produces an accessible currency string, but the plain-number
    /// fallback benefits from an explicit hint.
    var accessibleDescription: String {
        if currencyCode?.isEmpty == false {
            return formatted
        }
        return String(localized: "\(formatted), currency unknown")
    }

    /// Two amounts can only be compared when they share a currency.
    func canCompare(with other: Money) -> Bool {
        currencyCode == other.currencyCode
    }
}

nonisolated extension Money {
    /// Sum of same-currency amounts. Returns `nil` when the values are mixed,
    /// rather than producing a meaningless total.
    static func total(of values: [Money]) -> Money? {
        guard let first = values.first else { return nil }
        guard values.allSatisfy({ $0.currencyCode == first.currencyCode }) else { return nil }
        let sum = values.reduce(Decimal.zero) { $0 + $1.amount }
        return Money(amount: sum, currencyCode: first.currencyCode)
    }
}
