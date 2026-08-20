//
//  WebPageProvider.swift
//  Wishlist
//
//  The provider that always works and never needs a key: fetch the product
//  page and read the structured data retailers already publish for search
//  engines. It is the backstop for every store the app has no API for.
//

import Foundation

nonisolated struct WebPageProvider: ProductDataProvider {
    let identifier = "web-page"
    let displayName = String(localized: "Product page")
    let progressMessage = String(localized: "Reading the product page…")

    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool {
        credentials.allowsWebPageLookup && request.link != nil
    }

    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot {
        guard let link = request.link else { throw LookupError.noProductData }

        // A page fetched while resolving a shortened link is reused rather
        // than downloaded a second time.
        let body: Data
        let contentType: String?
        if let prefetched = request.prefetchedPage {
            body = prefetched.data
            contentType = prefetched.contentType
        } else {
            let response = try await http.send(
                Self.makeRequest(for: link.canonicalURL),
                provider: displayName
            )
            body = response.data
            contentType = response.headerValue("Content-Type")
        }

        // Decoded once, then read twice: the generic structured-data pass, and
        // for Amazon its own markup, which is the only thing on those pages
        // that actually carries a price.
        let html = HTMLParser.decode(body, contentTypeHeader: contentType)
        let document = HTMLParser.parse(html)

        var snapshot = StructuredDataParser.parse(
            document: document,
            link: link,
            sourceName: displayName
        )
        if link.isAmazon {
            snapshot = snapshot.merging(
                AmazonPageParser.snapshot(from: html, link: link, sourceName: displayName)
            )
        }

        guard !snapshot.isEmpty else { throw LookupError.noProductData }
        return snapshot
    }

    /// Retailers serve very different markup to clients that do not look like a
    /// browser — often no structured data at all — so the request advertises
    /// itself honestly as a page view.
    static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(2).joined(separator: ","),
                         forHTTPHeaderField: "Accept-Language")
        return request
    }
}
