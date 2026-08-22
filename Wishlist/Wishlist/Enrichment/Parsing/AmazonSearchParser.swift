//
//  AmazonSearchParser.swift
//  Wishlist
//
//  Reads Amazon's own search results page.
//
//  There is no free, keyless product search API worth relying on. What there
//  is, is a retailer that already runs a very good search — so rather than
//  pretend to search, Wishlist asks the store and reads the answer with the
//  same free page reader it uses everywhere else. Nothing here is guessed: a
//  result is only offered if the page carried an identifier and a title for it.
//

import Foundation

nonisolated enum AmazonSearchParser {
    /// Result cards are keyed by this attribute, which also carries the ASIN.
    private static let cardMarker = "data-asin=\""
    /// The result thumbnail. Its `alt` is the product title on every Amazon
    /// storefront, which is a tidier title than the truncated heading text.
    private static let imageMarker = "class=\"s-image\""
    private static let priceMarker = "class=\"a-offscreen\""

    /// Amazon serves a challenge page to clients it does not recognise. It has
    /// none of the markers below and plenty of these phrases.
    static func looksLikeBotCheck(_ html: String) -> Bool {
        guard !html.contains(cardMarker) else { return false }
        let markers = [
            "Enter the characters you see below",
            "Robot Check",
            "automated access",
            "captcha"
        ]
        let sample = html.prefix(20_000).lowercased()
        return markers.contains { sample.contains($0.lowercased()) }
    }

    static func candidates(
        in html: String,
        marketplace: AmazonMarketplace,
        limit: Int = 10
    ) -> [ProductCandidate] {
        var results: [ProductCandidate] = []
        var seen = Set<String>()
        var cursor = html.startIndex

        while results.count < limit,
              let markerRange = html.range(of: cardMarker, range: cursor..<html.endIndex) {
            // Everything up to the next card is this card's markup.
            let nextMarker = html.range(of: cardMarker, range: markerRange.upperBound..<html.endIndex)
            let cardEnd = nextMarker?.lowerBound ?? html.endIndex
            let card = String(html[markerRange.upperBound..<cardEnd])
            cursor = markerRange.upperBound

            guard let asin = card.prefix(while: { $0 != "\"" }).nilIfEmpty,
                  URLValidator.isValidASIN(asin),
                  !seen.contains(asin)
            else { continue }

            let imageAttributes = HTMLParser.attributes(ofFirstTagContaining: imageMarker, in: card)
            guard let title = imageAttributes["alt"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.count > 3
            else { continue }

            guard let productURL = URL(string: "https://\(marketplace.rawValue)/dp/\(asin)") else {
                continue
            }

            seen.insert(asin)
            results.append(
                ProductCandidate(
                    id: asin,
                    name: title,
                    price: PriceParser.parse(
                        HTMLParser.firstElementText(containing: priceMarker, in: card),
                        currencyHint: marketplace.currencyCode
                    ),
                    imageURL: imageAttributes["src"].flatMap { URL(string: $0) },
                    productURL: productURL,
                    retailer: Retailer(name: "Amazon", domain: marketplace.domain)
                )
            )
        }
        return results
    }
}

private extension Substring {
    var nilIfEmpty: String? {
        isEmpty ? nil : String(self)
    }
}
