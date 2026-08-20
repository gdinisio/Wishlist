//
//  WishlistItem.swift
//  Wishlist
//
//  The single normalised model the whole app works with. No view and no store
//  ever sees a provider's response shape — everything is funnelled into this.
//

import Foundation

nonisolated struct WishlistItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    /// The retailer's own full title, present only when `name` is a shortened
    /// form of it. Shown on the item's screen so nothing is hidden.
    var fullName: String?
    var imageURL: URL?
    var productURL: URL?
    var price: Money?
    var retailer: Retailer?
    var availability: Availability
    var brand: String?
    var category: String?
    /// Optional grouping the user assigns, e.g. "Kitchen" or "Gifts". Plain
    /// text rather than a separate entity: a wishlist does not need a taxonomy,
    /// and this keeps items self-contained for a future sync.
    var collectionName: String?
    var details: String?
    var dateAdded: Date
    var dateObtained: Date?
    var status: ItemStatus
    var notes: String?

    /// Every price Wishlist has actually observed, oldest first.
    var priceHistory: [PricePoint]
    /// When product data was last successfully refreshed from a provider.
    var dateRefreshed: Date?
    /// Names of the providers that contributed data, for the detail view's
    /// "where this came from" line.
    var sources: [String]
    /// Bumped on every local mutation. Present so a future iCloud layer has a
    /// last-writer-wins field to merge on without a schema migration.
    var dateModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        fullName: String? = nil,
        imageURL: URL? = nil,
        productURL: URL? = nil,
        price: Money? = nil,
        retailer: Retailer? = nil,
        availability: Availability = .unknown,
        brand: String? = nil,
        category: String? = nil,
        collectionName: String? = nil,
        details: String? = nil,
        dateAdded: Date = .now,
        dateObtained: Date? = nil,
        status: ItemStatus = .active,
        notes: String? = nil,
        priceHistory: [PricePoint] = [],
        dateRefreshed: Date? = nil,
        sources: [String] = [],
        dateModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.imageURL = imageURL
        self.productURL = productURL
        self.price = price
        self.retailer = retailer
        self.availability = availability
        self.brand = brand
        self.category = category
        self.collectionName = collectionName
        self.details = details
        self.dateAdded = dateAdded
        self.dateObtained = dateObtained
        self.status = status
        self.notes = notes
        self.priceHistory = priceHistory
        self.dateRefreshed = dateRefreshed
        self.sources = sources
        self.dateModified = dateModified
    }

    // `description` is spelled `details` in Swift to avoid colliding with
    // `CustomStringConvertible`, but persists under its natural key.
    private enum CodingKeys: String, CodingKey {
        case id, name, fullName, imageURL, productURL, price, retailer, availability
        case brand, category, collectionName
        case details = "description"
        case dateAdded, dateObtained, status, notes
        case priceHistory, dateRefreshed, sources, dateModified
    }
}

// MARK: - Derived values

nonisolated extension WishlistItem {
    var isObtained: Bool { status == .obtained }

    /// The name to show when a lookup could not find one.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Item") : trimmed
    }

    /// The store name to show, falling back to the product URL's host so a row
    /// never reads "Unknown" when the link itself tells us where it came from.
    var displayRetailer: String? {
        if let name = retailer?.name, !name.isEmpty { return name }
        guard let host = productURL?.host() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// The first price Wishlist ever recorded, used to describe a price change.
    var originalPrice: Money? { priceHistory.first?.price }

    /// A price change worth surfacing: same currency, and actually different.
    var priceChange: PriceChange? {
        guard let current = price, let original = originalPrice,
              current.canCompare(with: original), current.amount != original.amount
        else { return nil }
        return PriceChange(
            original: original,
            current: current,
            difference: Money(amount: current.amount - original.amount, currencyCode: current.currencyCode)
        )
    }

    /// Whether this item's price fits inside an amount. Only comparable when
    /// the currencies match — an unknown price never "fits", because saying so
    /// would be a guess.
    func fits(within budget: Money) -> Bool {
        guard let price, price.canCompare(with: budget) else { return false }
        return price.amount <= budget.amount
    }

    /// How far over an amount this item is, when it is over and comparable.
    func amountOver(_ budget: Money) -> Money? {
        guard let price, price.canCompare(with: budget), price.amount > budget.amount else {
            return nil
        }
        return Money(amount: price.amount - budget.amount, currencyCode: price.currencyCode)
    }

    /// Fields a lookup was unable to fill. Drives the "some details are
    /// missing" affordance instead of showing invented values.
    var missingFields: [String] {
        var missing: [String] = []
        if price == nil { missing.append(String(localized: "price")) }
        if imageURL == nil { missing.append(String(localized: "image")) }
        if displayRetailer == nil { missing.append(String(localized: "store")) }
        return missing
    }
}

nonisolated struct PriceChange: Hashable, Sendable {
    var original: Money
    var current: Money
    var difference: Money

    var isDrop: Bool { difference.amount < 0 }

    var magnitude: Money {
        Money(amount: abs(difference.amount), currencyCode: difference.currencyCode)
    }

    var symbolName: String { isDrop ? "arrow.down" : "arrow.up" }

    var label: String {
        isDrop
            ? String(localized: "\(magnitude.formatted) less than when you added it")
            : String(localized: "\(magnitude.formatted) more than when you added it")
    }

    var compactLabel: String { magnitude.formatted }
}

// MARK: - Mutation helpers
//
// Kept on the model so every change funnels through one place that keeps
// `dateModified` and the price history honest.

nonisolated extension WishlistItem {
    mutating func touch(_ date: Date = .now) {
        dateModified = date
    }

    mutating func markObtained(on date: Date = .now) {
        status = .obtained
        dateObtained = date
        touch(date)
    }

    mutating func returnToWishlist(_ date: Date = .now) {
        status = .active
        dateObtained = nil
        touch(date)
    }

    /// Records a newly observed price, appending to the history only when the
    /// value actually changed.
    mutating func recordPrice(_ newPrice: Money?, observed date: Date = .now) {
        guard let newPrice else { return }
        if let last = priceHistory.last?.price, last == newPrice {
            price = newPrice
            touch(date)
            return
        }
        price = newPrice
        priceHistory.append(PricePoint(date: date, price: newPrice))
        // Bound the history so a long-lived item cannot grow without limit.
        if priceHistory.count > 60 {
            priceHistory.removeFirst(priceHistory.count - 60)
        }
        touch(date)
    }
}
