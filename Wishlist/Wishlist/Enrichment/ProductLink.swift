//
//  ProductLink.swift
//  Wishlist
//
//  A URL that has been through validation: cleaned of tracking parameters,
//  attributed to a retailer, and — when it is an Amazon link — reduced to the
//  ASIN that identifies the product across every one of Amazon's storefronts.
//

import Foundation

nonisolated struct ProductLink: Hashable, Sendable {
    /// The address as typed or pasted.
    var originalURL: URL
    /// Canonical address: tracking parameters removed, Amazon links reduced to
    /// `/dp/<ASIN>`. This is what gets saved and what duplicates compare on.
    var canonicalURL: URL
    var host: String
    var retailer: Retailer
    var amazonASIN: String?
    var amazonMarketplace: AmazonMarketplace?
    /// Shortened links (amzn.to, a.co, bit.ly …) must be followed before the
    /// real product can be identified.
    var isShortened: Bool

    var isAmazon: Bool { amazonMarketplace != nil }

    /// The currency this storefront trades in: certain for an Amazon
    /// marketplace, strongly implied by a country domain, and unknown for a
    /// `.com` that could be anywhere.
    var storefrontCurrency: String? {
        if let amazonMarketplace { return amazonMarketplace.currencyCode }
        return CurrencyRegion.currency(forHost: host)
    }

    /// Whether the storefront's currency is a fact rather than an inference.
    /// Amazon's marketplaces each trade in exactly one currency, so a price
    /// read from amazon.co.uk is in pounds whatever symbol happened to be
    /// scraped alongside it.
    var isCurrencyCertain: Bool { amazonMarketplace != nil }

    /// Used when a price is found without a currency of its own. Never used to
    /// invent a missing price.
    var currencyHint: String? { storefrontCurrency }
}
