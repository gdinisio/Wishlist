//
//  RainforestProvider.swift
//  Wishlist
//
//  Rainforest API returns structured Amazon product data from an ASIN or a
//  search term without Associates credentials, which makes it the practical
//  fallback for Amazon links when the Product Advertising API is not set up.
//

import Foundation

nonisolated struct RainforestProvider: ProductDataProvider {
    let identifier = "rainforest"
    let displayName = String(localized: "Rainforest")
    let progressMessage = String(localized: "Looking up on Amazon…")

    private let http: HTTPClient
    private let endpoint = URL(string: "https://api.rainforestapi.com/request")!

    init(http: HTTPClient) {
        self.http = http
    }

    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool {
        guard credentials.hasRainforest else { return false }
        if request.link?.amazonASIN != nil { return true }
        return request.link == nil && request.searchTerm?.isEmpty == false
    }

    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot {
        guard let key = credentials.rainforestKey else {
            throw LookupError.notAuthorized(provider: displayName)
        }
        let marketplace = request.link?.amazonMarketplace ?? credentials.amazonMarketplace

        var query: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "amazon_domain", value: marketplace.domain)
        ]
        if let asin = request.link?.amazonASIN {
            query.append(URLQueryItem(name: "type", value: "product"))
            query.append(URLQueryItem(name: "asin", value: asin))
        } else if let term = request.searchTerm, !term.isEmpty {
            query.append(URLQueryItem(name: "type", value: "search"))
            query.append(URLQueryItem(name: "search_term", value: term))
        } else {
            throw LookupError.noProductData
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        components.queryItems = query
        guard let url = components.url else {
            throw LookupError.providerUnavailable(provider: displayName)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await http.send(urlRequest, provider: displayName)
        guard let json = JSONValue.parse(response.data) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        if case .bool(false) = json.value(at: "request_info.success") ?? .null {
            throw LookupError.notFound
        }

        if let product = json["product"] {
            return snapshot(fromProduct: product, marketplace: marketplace)
        }
        if let result = json.value(at: "search_results.0") {
            return snapshot(fromSearchResult: result, marketplace: marketplace)
        }
        throw LookupError.noProductData
    }

    private func snapshot(fromProduct product: JSONValue, marketplace: AmazonMarketplace) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.sources = [displayName]
        snapshot.retailer = Retailer(name: "Amazon", domain: marketplace.domain)
        snapshot.name = product["title"]?.stringValue

        if let imageString = product.value(at: "main_image.link")?.stringValue
            ?? product.value(at: "images.0.link")?.stringValue {
            snapshot.imageURL = URL(string: imageString)
        }
        if let urlString = product["link"]?.stringValue {
            snapshot.productURL = URL(string: urlString)
        }
        snapshot.brand = product["brand"]?.stringValue
        snapshot.category = product.value(at: "categories")?.arrayValue
            .compactMap { $0["name"]?.stringValue }
            .last
        if let description = product["description"]?.stringValue {
            snapshot.details = HTMLParser.plainText(from: description)
        }

        // The buy box carries the price a shopper would actually pay.
        let buybox = product["buybox_winner"]
        let priceNode = buybox?["price"] ?? product["price"] ?? product.value(at: "buybox_winner.rrp")
        if let amount = priceNode?["value"]?.decimalValue, amount > 0 {
            let currency = priceNode?["currency"]?.stringValue ?? marketplace.currencyCode
            snapshot.price = Money(amount: amount, currencyCode: currency)
        } else if let raw = priceNode?["raw"]?.stringValue {
            snapshot.price = PriceParser.parse(raw, currencyHint: marketplace.currencyCode)
        }

        snapshot.availability = Availability.parse(
            buybox?.value(at: "availability.raw")?.stringValue
                ?? product.value(at: "availability.raw")?.stringValue
        )
        if snapshot.availability == .unknown, snapshot.price != nil {
            snapshot.availability = .inStock
        }
        return snapshot
    }

    private func snapshot(fromSearchResult result: JSONValue, marketplace: AmazonMarketplace) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.sources = [displayName]
        snapshot.retailer = Retailer(name: "Amazon", domain: marketplace.domain)
        snapshot.name = result["title"]?.stringValue
        if let imageString = result["image"]?.stringValue {
            snapshot.imageURL = URL(string: imageString)
        }
        if let urlString = result["link"]?.stringValue {
            snapshot.productURL = URL(string: urlString)
        } else if let asin = result["asin"]?.stringValue {
            snapshot.productURL = URL(string: "https://\(marketplace.rawValue)/dp/\(asin)")
        }
        if let amount = result.value(at: "price.value")?.decimalValue, amount > 0 {
            let currency = result.value(at: "price.currency")?.stringValue ?? marketplace.currencyCode
            snapshot.price = Money(amount: amount, currencyCode: currency)
        }
        if snapshot.price != nil { snapshot.availability = .inStock }
        return snapshot
    }
}
