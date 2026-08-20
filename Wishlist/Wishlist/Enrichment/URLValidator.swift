//
//  URLValidator.swift
//  Wishlist
//
//  Step one of the lookup pipeline. Accepts what a person actually pastes —
//  a bare domain, a share sheet URL with forty characters of tracking, a
//  shortened link — and either produces a `ProductLink` or an error that says
//  which of those it could not make sense of.
//

import Foundation

nonisolated enum URLValidator {
    /// Query parameters that never identify a product and only make duplicate
    /// detection harder.
    private static let trackingParameters: Set<String> = [
        "tag", "ref", "ref_", "linkcode", "linkid", "ascsubtag", "creative",
        "creativeasin", "camp", "smid", "psc", "th", "qid", "sr", "sprefix",
        "crid", "keywords", "dib", "dib_tag", "content-id", "_encoding",
        "pd_rd_i", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_p", "pf_rd_r",
        "pf_rd_s", "pf_rd_t", "pf_rd_i", "pf_rd_m", "spm", "spLa",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "gclid", "fbclid", "msclkid", "mc_cid", "mc_eid",
        "srsltid", "gad_source", "irclickid", "irgwc", "cm_mmc", "cm_sp",
        "source", "referrer", "affiliate", "aff", "clickid", "sid"
    ]

    private static let shortenerHosts: Set<String> = [
        "amzn.to", "amzn.eu", "amzn.asia", "a.co", "bit.ly", "tinyurl.com",
        "t.co", "goo.gl", "ow.ly", "buff.ly", "shorturl.at", "s.click.aliexpress.com",
        "ebay.us", "rstyle.me", "shop.app", "lnk.to", "spr.ly"
    ]

    /// Parses arbitrary user input into a validated product link.
    static func validate(_ input: String) throws -> ProductLink {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LookupError.invalidURL }

        // People paste "amazon.co.uk/dp/…" without a scheme all the time.
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let rawHost = components.host?.lowercased(),
              !rawHost.isEmpty
        else { throw LookupError.invalidURL }

        guard scheme == "http" || scheme == "https" else {
            throw LookupError.unsupportedURL(host: components.host)
        }
        // A host with no dot is a search term, not an address.
        guard rawHost.contains("."), !rawHost.hasSuffix(".") else {
            throw LookupError.invalidURL
        }

        components.scheme = "https"
        components.host = rawHost
        components.fragment = nil
        components.queryItems = cleanedQueryItems(components.queryItems)

        guard let originalURL = URL(string: candidate),
              let cleanedURL = components.url
        else { throw LookupError.invalidURL }

        let isShortened = shortenerHosts.contains(rawHost)
        let marketplace = AmazonMarketplace.matching(host: rawHost)
        let asin = marketplace == nil ? nil : extractASIN(from: components)

        var canonical = cleanedURL
        if let marketplace, let asin,
           let tidy = URL(string: "https://\(marketplace.rawValue)/dp/\(asin)") {
            canonical = tidy
        }

        return ProductLink(
            originalURL: originalURL,
            canonicalURL: canonical,
            host: rawHost,
            retailer: RetailerIdentifier.retailer(forHost: rawHost),
            amazonASIN: asin,
            amazonMarketplace: marketplace,
            isShortened: isShortened
        )
    }

    /// Lenient check used to decide whether the Add screen should treat typed
    /// text as a link or as a product name. Never throws.
    static func looksLikeURL(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        if trimmed.contains("://") { return true }
        guard let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex else { return false }
        let afterDot = trimmed[trimmed.index(after: dot)...]
        return afterDot.count >= 2 && afterDot.first?.isLetter == true
    }

    private static func cleanedQueryItems(_ items: [URLQueryItem]?) -> [URLQueryItem]? {
        guard let items, !items.isEmpty else { return nil }
        let kept = items.filter { !trackingParameters.contains($0.name.lowercased()) }
        return kept.isEmpty ? nil : kept
    }

    /// Finds the ten-character ASIN in any of Amazon's URL shapes.
    static func extractASIN(from components: URLComponents) -> String? {
        if let queryASIN = components.queryItems?
            .first(where: { $0.name.lowercased() == "asin" })?.value,
           isValidASIN(queryASIN) {
            return queryASIN.uppercased()
        }

        let segments = components.path
            .split(separator: "/")
            .map(String.init)

        // /dp/B08N5WRWNW, /gp/product/B08N5WRWNW, /gp/aw/d/B08N5WRWNW,
        // /product/B08N5WRWNW, /dp/product/B08N5WRWNW
        let markers: Set<String> = ["dp", "product", "d", "gp", "asin"]
        for (index, segment) in segments.enumerated() where markers.contains(segment.lowercased()) {
            for candidate in segments.dropFirst(index + 1).prefix(2) where isValidASIN(candidate) {
                return candidate.uppercased()
            }
        }
        // Last resort: any segment that is exactly an ASIN.
        return segments.first(where: isValidASIN)?.uppercased()
    }

    /// ASINs are ten alphanumeric characters, and start with "B" for everything
    /// that is not a book (books use their ISBN-10).
    static func isValidASIN(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isNumber || $0.isLetter) }
    }
}
