//
//  StructuredDataParser.swift
//  Wishlist
//
//  Reads the structured product data most retailers already publish for search
//  engines: schema.org JSON-LD first (richest and most reliable), then Open
//  Graph and Twitter card meta tags to fill the gaps.
//
//  Every value here comes from something the page explicitly declared. Where a
//  page declares nothing, the field stays `nil` and the UI says so.
//

import Foundation

nonisolated enum StructuredDataParser {
    static func parse(
        document: HTMLDocument,
        link: ProductLink,
        sourceName: String
    ) -> ProductSnapshot {
        let fromJSONLD = productSnapshot(fromJSONLD: document.jsonLDBlocks, currencyHint: link.currencyHint)
        let fromMeta = productSnapshot(fromMeta: document, currencyHint: link.currencyHint)

        var merged = fromJSONLD.merging(fromMeta)
        if merged.name == nil {
            merged.name = cleanedTitle(document.title, retailer: link.retailer.name)
        }
        merged.productURL = merged.productURL ?? link.canonicalURL
        merged.retailer = merged.retailer ?? link.retailer
        merged.imageURL = merged.imageURL.map { absoluteURL($0, relativeTo: link.canonicalURL) }
        if !merged.isEmpty { merged.sources = [sourceName] }
        return merged
    }

    // MARK: - JSON-LD

    static func productSnapshot(fromJSONLD blocks: [String], currencyHint: String?) -> ProductSnapshot {
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let root = JSONValue.parse(data),
                  let product = findProductNode(in: root)
            else { continue }
            let parsed = productSnapshot(fromProductNode: product, currencyHint: currencyHint)
            if !parsed.isEmpty { return parsed }
        }
        return ProductSnapshot()
    }

    /// Walks the JSON tree looking for a node whose `@type` mentions a product.
    /// Handles the `@graph` wrapper and the arrays sites nest their data in.
    private static func findProductNode(in value: JSONValue, depth: Int = 0) -> JSONValue? {
        guard depth < 6 else { return nil }

        if isProductNode(value) { return value }

        if case .array(let elements) = value {
            for element in elements {
                if let found = findProductNode(in: element, depth: depth + 1) { return found }
            }
            return nil
        }

        guard case .object(let dictionary) = value else { return nil }

        if let graph = dictionary["@graph"] {
            if let found = findProductNode(in: graph, depth: depth + 1) { return found }
        }
        for (key, child) in dictionary where key != "@graph" {
            if let found = findProductNode(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func isProductNode(_ value: JSONValue) -> Bool {
        guard case .object = value, let type = value["@type"] else { return false }
        let types = type.arrayValue.compactMap(\.stringValue).map { $0.lowercased() }
        return types.contains { candidate in
            candidate.contains("product") || candidate == "book"
                || candidate == "vehicle" || candidate == "softwareapplication"
        }
    }

    private static func productSnapshot(fromProductNode node: JSONValue, currencyHint: String?) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.name = node["name"]?.stringValue ?? node["title"]?.stringValue
        snapshot.brand = brandName(from: node["brand"])
        snapshot.category = categoryName(from: node["category"])
        snapshot.imageURL = imageURL(from: node["image"])
        if let description = node["description"]?.stringValue {
            snapshot.details = HTMLParser.plainText(from: description)
        }
        if let urlString = node["url"]?.stringValue {
            snapshot.productURL = URL(string: urlString)
        }

        if let offer = firstOffer(in: node) {
            let currency = offer["priceCurrency"]?.stringValue
                ?? offer.value(at: "priceSpecification.priceCurrency")?.stringValue
                ?? currencyHint
            let rawPrice = offer["price"]
                ?? offer.value(at: "priceSpecification.price")
                ?? offer["lowPrice"]
            if let amount = rawPrice?.decimalValue, amount > 0 {
                snapshot.price = Money(amount: amount, currencyCode: currency)
            }
            snapshot.availability = Availability.parse(
                offer["availability"]?.stringValue ?? offer["itemCondition"]?.stringValue
            )
        }
        return snapshot
    }

    /// Offers can be an object, an array, or an AggregateOffer wrapping more
    /// offers. Prefer one that actually carries a price.
    private static func firstOffer(in node: JSONValue) -> JSONValue? {
        guard let offers = node["offers"] else { return nil }
        var candidates = offers.arrayValue
        for candidate in candidates {
            if let nested = candidate["offers"] {
                candidates.append(contentsOf: nested.arrayValue)
            }
        }
        return candidates.first { $0["price"] != nil || $0.value(at: "priceSpecification.price") != nil }
            ?? candidates.first { $0["lowPrice"] != nil }
            ?? candidates.first
    }

    private static func brandName(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let name = value.stringValue { return name }
        return value.arrayValue.first?["name"]?.stringValue ?? value["name"]?.stringValue
    }

    private static func categoryName(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let name = value.stringValue {
            // Breadcrumb-style categories: keep the most specific segment.
            let segments = name.split(whereSeparator: { $0 == ">" || $0 == "|" || $0 == "/" })
            return segments.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
        }
        return value.arrayValue.compactMap(\.stringValue).last
            ?? value["name"]?.stringValue
    }

    private static func imageURL(from value: JSONValue?) -> URL? {
        guard let value else { return nil }
        for candidate in value.arrayValue {
            if let string = candidate.stringValue, let url = URL(string: string) { return url }
            if let string = candidate.firstString(["url", "contentUrl", "@id"]),
               let url = URL(string: string) { return url }
        }
        return nil
    }

    // MARK: - Open Graph and Twitter cards

    static func productSnapshot(fromMeta document: HTMLDocument, currencyHint: String?) -> ProductSnapshot {
        var snapshot = ProductSnapshot()

        snapshot.name = document.meta(["og:title", "twitter:title", "product:title"])
        snapshot.details = document
            .meta(["og:description", "twitter:description", "description"])
            .map { HTMLParser.plainText(from: $0) }
        snapshot.brand = document.meta(["product:brand", "og:brand", "brand"])
        snapshot.category = document.meta(["product:category", "article:section"])

        if let imageString = document.meta([
            "og:image:secure_url", "og:image", "twitter:image", "twitter:image:src", "image"
        ]) {
            snapshot.imageURL = URL(string: imageString)
        }
        if let urlString = document.meta(["og:url"]) ?? document.canonicalURL {
            snapshot.productURL = URL(string: urlString)
        }
        if let siteName = document.meta(["og:site_name"]) {
            snapshot.retailer = Retailer(name: siteName)
        }

        let currency = document.meta([
            "product:price:currency", "og:price:currency", "twitter:data2", "priceCurrency"
        ]) ?? currencyHint
        if let priceString = document.meta([
            "product:price:amount", "og:price:amount", "product:sale_price:amount", "price"
        ]) {
            snapshot.price = PriceParser.parse(priceString, currencyHint: currency)
        }
        snapshot.availability = Availability.parse(
            document.meta(["product:availability", "og:availability", "availability"])
        )
        return snapshot
    }

    // MARK: - Helpers

    /// Page titles are usually "Product Name | Retailer" or "Retailer: Product
    /// Name". Strip the retailer so a wishlist row reads cleanly.
    static func cleanedTitle(_ title: String?, retailer: String?) -> String? {
        guard var title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        let separators: [String] = [" | ", " – ", " — ", " - ", " :: "]
        if let retailer, !retailer.isEmpty {
            for separator in separators {
                let suffix = separator + retailer
                if title.lowercased().hasSuffix(suffix.lowercased()) {
                    title = String(title.dropLast(suffix.count))
                }
                let prefix = retailer + separator
                if title.lowercased().hasPrefix(prefix.lowercased()) {
                    title = String(title.dropFirst(prefix.count))
                }
            }
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Product images are often published as protocol-relative or root-relative
    /// paths.
    static func absoluteURL(_ url: URL, relativeTo base: URL) -> URL {
        if url.scheme != nil { return url }
        let string = url.absoluteString
        if string.hasPrefix("//"), let resolved = URL(string: "https:" + string) {
            return resolved
        }
        return URL(string: string, relativeTo: base)?.absoluteURL ?? url
    }
}
