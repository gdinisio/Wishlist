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
    let canProvidePrice = true

    private let http: HTTPClient
    private let models: LanguageModelRouter
    private let extractor = ProductExtractor()

    init(http: HTTPClient, models: LanguageModelRouter) {
        self.http = http
        self.models = models
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
                Self.makeRequest(for: link.canonicalURL, purpose: request.purpose),
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

        // Some retailers publish nothing a parser can use. If the user has
        // turned it on, a model reads the page's text and points at the values
        // — every one of which is then checked back against that text.
        if request.purpose == .full, needsAssistance(snapshot),
           credentials.intelligence.readsDifficultPages,
           let client = models.client(for: credentials.intelligence) {
            let digest = HTMLParser.textDigest(from: html)
            let assisted = await extractor.snapshot(
                fromPageText: digest,
                link: link,
                client: client
            )
            snapshot = snapshot.merging(assisted)
        }

        guard !snapshot.isEmpty else { throw LookupError.noProductData }
        return snapshot
    }

    /// Worth asking a model only when the two things that matter are missing.
    private func needsAssistance(_ snapshot: ProductSnapshot) -> Bool {
        snapshot.name == nil || snapshot.price == nil
    }

    /// Retailers serve very different markup to clients that do not look like a
    /// browser — often no structured data at all — so the request advertises
    /// itself honestly as a page view.
    static func makeRequest(for url: URL, purpose: LookupPurpose = .full) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if purpose == .priceCheck {
            // A cached copy would report the price we already have, which is
            // exactly the thing a refresh exists to find out has changed.
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
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
