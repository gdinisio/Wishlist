//
//  AmazonPageParser.swift
//  Wishlist
//
//  Amazon publishes almost no schema.org data on its product pages, so the
//  generic structured-data reader comes back nearly empty for the one retailer
//  people paste most. This reads Amazon's own markup instead — the same
//  elements a person looking at the page would read.
//
//  It is a best-effort fallback, not a replacement for the Product Advertising
//  API: Amazon serves a bot check to unfamiliar clients often enough that this
//  cannot be relied on. When it returns nothing, the chain simply moves on.
//

import Foundation

nonisolated enum AmazonPageParser {
    /// Blocks Amazon renders the buy-box price into, most specific first.
    private static let priceContainers = [
        "corePriceDisplay_desktop_feature_div",
        "corePriceDisplay_mobile_feature_div",
        "corePrice_feature_div",
        "apex_desktop",
        "apex_mobile"
    ]

    /// Amazon writes the accessible price into a visually hidden span, which is
    /// both the cleanest string on the page and the one meant to be read aloud.
    private static let priceElement = "class=\"a-offscreen\""

    static func snapshot(from html: String, link: ProductLink, sourceName: String) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.retailer = link.retailer
        snapshot.productURL = link.canonicalURL
        snapshot.name = HTMLParser.elementText(id: "productTitle", in: html)
        snapshot.price = price(in: html, currencyHint: link.currencyHint)
        snapshot.imageURL = imageURL(in: html)

        snapshot.availability = Availability.parse(
            HTMLParser.elementText(id: "availability", in: html, limit: 400)
        )
        // A buy box with a price in it is a live listing.
        if snapshot.availability == .unknown, snapshot.price != nil {
            snapshot.availability = .inStock
        }

        if let byline = HTMLParser.elementText(id: "bylineInfo", in: html, limit: 200) {
            snapshot.brand = brand(fromByline: byline)
        }

        if !snapshot.isEmpty { snapshot.sources = [sourceName] }
        return snapshot
    }

    private static func price(in html: String, currencyHint: String?) -> Money? {
        for container in priceContainers {
            if let text = HTMLParser.firstElementText(containing: priceElement, in: html, after: container),
               let money = PriceParser.parse(text, currencyHint: currencyHint) {
                return money
            }
        }
        // Nothing matched a known block: the first hidden price on the page is
        // still far more likely to be the buy-box price than anything else.
        guard let text = HTMLParser.firstElementText(containing: priceElement, in: html) else {
            return nil
        }
        return PriceParser.parse(text, currencyHint: currencyHint)
    }

    private static func imageURL(in html: String) -> URL? {
        let candidates = [
            HTMLParser.elementAttribute("data-old-hires", id: "landingImage", in: html),
            HTMLParser.elementAttribute("src", id: "landingImage", in: html),
            HTMLParser.elementAttribute("src", id: "imgBlkFront", in: html),
            HTMLParser.elementAttribute("src", id: "main-image", in: html)
        ]
        for candidate in candidates.compactMap({ $0 }) {
            // Amazon uses data: placeholders while the real image loads.
            guard !candidate.hasPrefix("data:"), let url = URL(string: candidate) else { continue }
            return url
        }
        return nil
    }

    /// The byline reads "Visit the Sony Store" or "Brand: Sony"; neither is a
    /// brand name until it is trimmed.
    private static func brand(fromByline byline: String) -> String? {
        var value = byline.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Visit the ", "Brand: ", "by "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if value.hasSuffix(" Store") {
            value = String(value.dropLast(" Store".count))
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // A byline that is a sentence rather than a name is not a brand.
        guard !value.isEmpty, value.count <= 40 else { return nil }
        return value
    }
}
