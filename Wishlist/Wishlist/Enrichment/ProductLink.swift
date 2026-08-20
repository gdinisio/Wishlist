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

    /// Currency implied by the storefront. Used only as a hint when a price
    /// carries an ambiguous symbol, never to invent a missing price.
    var currencyHint: String? { amazonMarketplace?.currencyCode }
}
