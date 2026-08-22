//
//  ProductSearchService.swift
//  Wishlist
//
//  Finding a product by name, for free.
//
//  The design admits something honestly: there is no dependable, keyless
//  product-search API. So this does not pretend to search. It asks a retailer
//  to search — using the storefront the user already shops at — and reads the
//  results page with the same free reader the rest of the app uses. The user
//  picks the right one, and that choice then goes through the ordinary lookup
//  chain against the product's own page, so what gets saved is exactly as
//  verified as a pasted link.
//

import Foundation
import OSLog

nonisolated struct ProductSearchService: Sendable {
    private let http: HTTPClient
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "search")

    init(http: HTTPClient) {
        self.http = http
    }

    /// Builds the search phrase from what the user typed plus any details they
    /// gave. Colour and size are exactly the words that separate one variant
    /// from another, so they belong in the query.
    static func query(name: String, colour: String?, size: String?) -> String {
        var parts = [name.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let colour = colour?.trimmingCharacters(in: .whitespacesAndNewlines), !colour.isEmpty {
            parts.append(colour)
        }
        if let size = size?.trimmingCharacters(in: .whitespacesAndNewlines), !size.isEmpty {
            parts.append(size)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    func search(
        query: String,
        marketplace: AmazonMarketplace
    ) async throws -> [ProductCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "https://\(marketplace.rawValue)/s") else {
            throw LookupError.providerUnavailable(provider: "Amazon")
        }
        components.queryItems = [URLQueryItem(name: "k", value: trimmed)]
        guard let url = components.url else {
            throw LookupError.providerUnavailable(provider: "Amazon")
        }

        let response = try await http.send(
            WebPageProvider.makeRequest(for: url),
            provider: String(localized: "Amazon")
        )
        let html = HTMLParser.decode(
            response.data,
            contentTypeHeader: response.headerValue("Content-Type")
        )

        // A bot check is a page too, and it parses to nothing. Say so rather
        // than showing an empty list as though the product does not exist.
        if AmazonSearchParser.looksLikeBotCheck(html) {
            log.notice("Amazon returned a bot check for a search")
            throw LookupError.providerRejected(
                provider: String(localized: "Amazon"),
                detail: String(localized: "Amazon asked for a human check instead of results. Paste a link instead, or try again shortly.")
            )
        }

        return AmazonSearchParser.candidates(in: html, marketplace: marketplace)
    }
}
