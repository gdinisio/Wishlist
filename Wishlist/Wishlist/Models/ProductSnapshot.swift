//
//  ProductSnapshot.swift
//  Wishlist
//
//  The normalised result of a product lookup. Providers translate their own
//  responses into this; the merger combines several of them; the UI only ever
//  sees this shape. Every field is optional because every field can genuinely
//  be unavailable — and an unavailable field is reported as such, never filled
//  in with a guess.
//

import Foundation

nonisolated struct ProductSnapshot: Hashable, Sendable {
    var name: String?
    /// The retailer's own full title, kept when `name` has been shortened.
    var fullName: String?
    var imageURL: URL?
    var productURL: URL?
    var price: Money?
    var retailer: Retailer?
    var availability: Availability
    var brand: String?
    var category: String?
    var details: String?

    /// Provider display names that contributed to this snapshot, in the order
    /// they were consulted.
    var sources: [String]

    init(
        name: String? = nil,
        fullName: String? = nil,
        imageURL: URL? = nil,
        productURL: URL? = nil,
        price: Money? = nil,
        retailer: Retailer? = nil,
        availability: Availability = .unknown,
        brand: String? = nil,
        category: String? = nil,
        details: String? = nil,
        sources: [String] = []
    ) {
        self.name = name
        self.fullName = fullName
        self.imageURL = imageURL
        self.productURL = productURL
        self.price = price
        self.retailer = retailer
        self.availability = availability
        self.brand = brand
        self.category = category
        self.details = details
        self.sources = sources
    }

    /// Nothing usable was found.
    var isEmpty: Bool {
        name == nil && price == nil && imageURL == nil && brand == nil && details == nil
    }

    /// Enough was found to be worth showing, but the headline fields are thin.
    var isPartial: Bool {
        !isEmpty && (name == nil || price == nil || imageURL == nil)
    }

    /// Fills only the fields this snapshot is missing, leaving existing values
    /// untouched. This is what makes the provider chain additive: a first
    /// provider can supply the price and a second the image.
    func merging(_ other: ProductSnapshot) -> ProductSnapshot {
        var merged = self
        merged.name = name ?? other.name
        merged.fullName = fullName ?? other.fullName
        merged.imageURL = imageURL ?? other.imageURL
        merged.productURL = productURL ?? other.productURL
        merged.price = price ?? other.price
        merged.retailer = retailer ?? other.retailer
        merged.brand = brand ?? other.brand
        merged.category = category ?? other.category
        merged.details = details ?? other.details
        if availability == .unknown { merged.availability = other.availability }
        for source in other.sources where !merged.sources.contains(source) {
            merged.sources.append(source)
        }
        return merged
    }

    /// Builds the item that will be saved. The name is the one field Wishlist
    /// insists on, so a caller-supplied fallback is required.
    func makeItem(fallbackName: String, requestedURL: URL?) -> WishlistItem {
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (resolvedName?.isEmpty == false ? resolvedName! : fallbackName)
        var item = WishlistItem(
            name: finalName,
            fullName: fullName,
            imageURL: imageURL,
            productURL: productURL ?? requestedURL,
            price: price,
            retailer: retailer,
            availability: availability,
            brand: brand,
            category: category,
            details: details,
            sources: sources
        )
        if let price {
            item.priceHistory = [PricePoint(date: .now, price: price)]
        }
        item.dateRefreshed = sources.isEmpty ? nil : .now
        return item
    }
}
