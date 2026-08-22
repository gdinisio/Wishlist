//
//  AmazonDataProvider.swift
//  Wishlist
//
//  Reads Amazon product data through whichever third-party service the user
//  has a key for.
//
//  Every field is resolved through a list of candidate paths rather than one
//  fixed shape. That is deliberate: these services return quite different JSON
//  for the same product, their shapes change without notice, and this code
//  cannot be tested against all of them. Breadth is worth more than precision
//  here — and anything that cannot be found simply stays unavailable, which is
//  the same promise the rest of the app makes.
//

import Foundation
import OSLog

nonisolated struct AmazonDataProvider: ProductDataProvider {
    let identifier = "amazon-data"
    let displayName = String(localized: "Amazon data service")
    let progressMessage = String(localized: "Looking up on Amazon…")
    let canProvidePrice = true

    private let http: HTTPClient
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "amazon-data")

    init(http: HTTPClient) {
        self.http = http
    }

    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool {
        let settings = credentials.amazonData
        guard settings.isConfigured, request.link?.amazonASIN != nil else { return false }
        // A routine refresh may be told to leave the allowance alone.
        if request.purpose == .priceCheck, !settings.usedForRefreshes { return false }
        return true
    }

    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot {
        guard let link = request.link, let asin = link.amazonASIN else {
            throw LookupError.noProductData
        }
        let marketplace = link.amazonMarketplace ?? credentials.amazonMarketplace
        let settings = credentials.amazonData

        guard let urlRequest = Self.makeRequest(
            settings: settings,
            asin: asin,
            marketplace: marketplace
        ) else {
            throw LookupError.providerRejected(
                provider: settings.service.displayName,
                detail: String(localized: "That service isn’t configured completely. Check its settings.")
            )
        }

        let response = try await http.sendAllowingHTTPError(urlRequest, provider: settings.service.displayName)
        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(from: response, service: settings.service)
        }
        guard let json = JSONValue.parse(response.data) else {
            throw LookupError.providerUnavailable(provider: settings.service.displayName)
        }

        AmazonDataUsage.recordRequest()

        // Most of these services answer with an array of results even for one
        // product; a few answer with the object directly.
        let node = Self.firstProductNode(in: json)
        let snapshot = Self.snapshot(
            from: node,
            marketplace: marketplace,
            asin: asin,
            serviceName: settings.service.displayName
        )
        guard !snapshot.isEmpty else { throw LookupError.noProductData }
        return snapshot
    }

    // MARK: - Requests

    static func makeRequest(
        settings: AmazonDataSettings,
        asin: String,
        marketplace: AmazonMarketplace
    ) -> URLRequest? {
        let productURL = "https://\(marketplace.rawValue)/dp/\(asin)"
        let key = (settings.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch settings.service {
        case .off:
            return nil

        case .apify:
            let actor = settings.actorIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "~")
            guard !actor.isEmpty, !key.isEmpty,
                  var components = URLComponents(
                    string: "https://api.apify.com/v2/acts/\(actor)/run-sync-get-dataset-items"
                  )
            else { return nil }
            components.queryItems = [URLQueryItem(name: "token", value: key)]
            guard let url = components.url else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            // Actors take a little while to start, so this waits longer than a
            // page fetch would.
            request.timeoutInterval = 90
            let body: JSONValue = [
                "startUrls": [["url": .string(productURL)]],
                "maxItems": 1
            ]
            request.httpBody = try? body.encoded()
            return request

        case .hasData:
            guard !key.isEmpty,
                  var components = URLComponents(string: "https://api.hasdata.com/scrape/amazon/product")
            else { return nil }
            components.queryItems = [
                URLQueryItem(name: "asin", value: asin),
                URLQueryItem(name: "domain", value: marketplace.domain)
            ]
            guard let url = components.url else { return nil }

            var request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 45
            return request

        case .custom:
            let filled = settings.urlTemplate
                .replacingOccurrences(of: "{asin}", with: asin)
                .replacingOccurrences(of: "{domain}", with: marketplace.domain)
                .replacingOccurrences(of: "{marketplace}", with: marketplace.rawValue)
            guard let url = URL(string: filled.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 45
            return request
        }
    }

    private static func failure(from response: HTTPResponse, service: AmazonDataService) -> LookupError {
        switch response.statusCode {
        case 401, 403:
            return .notAuthorized(provider: service.displayName)
        case 429:
            let retryAfter = response.headerValue("Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            // These services explain themselves better than we can guess.
            let detail = JSONValue.parse(response.data)
                .flatMap { json in
                    json.value(at: "error.message")?.stringValue
                        ?? json["message"]?.stringValue
                        ?? json["error"]?.stringValue
                }
            return .providerRejected(provider: service.displayName, detail: detail)
        }
    }

    // MARK: - Reading the answer

    /// Unwraps the several ways one product arrives: a bare object, the first
    /// of an array, or nested under a wrapper key.
    static func firstProductNode(in json: JSONValue) -> JSONValue {
        if case .array = json {
            return json[0] ?? json
        }
        for key in ["product", "data", "result", "results", "items"] {
            guard let nested = json[key] else { continue }
            if case .array = nested { return nested[0] ?? nested }
            return nested
        }
        return json
    }

    static func snapshot(
        from node: JSONValue,
        marketplace: AmazonMarketplace,
        asin: String,
        serviceName: String
    ) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.sources = [serviceName]
        snapshot.retailer = Retailer(name: "Amazon", domain: marketplace.domain)
        snapshot.productURL = URL(string: "https://\(marketplace.rawValue)/dp/\(asin)")

        snapshot.name = firstString(in: node, paths: Paths.title)
        snapshot.brand = firstString(in: node, paths: Paths.brand)
        snapshot.details = firstString(in: node, paths: Paths.description)
            .map { HTMLParser.plainText(from: $0) }

        if let imageString = firstString(in: node, paths: Paths.image) {
            snapshot.imageURL = URL(string: imageString)
        }

        let currency = firstString(in: node, paths: Paths.currency) ?? marketplace.currencyCode
        snapshot.price = price(in: node, currency: currency)
        snapshot.availability = availability(in: node)
        if snapshot.availability == .unknown, snapshot.price != nil {
            snapshot.availability = .inStock
        }
        return snapshot
    }

    private static func price(in node: JSONValue, currency: String) -> Money? {
        // A numeric field is unambiguous, so it is preferred.
        for path in Paths.priceValue {
            if let amount = node.value(at: path)?.decimalValue, amount > 0 {
                return Money(amount: amount, currencyCode: currency)
            }
        }
        // Otherwise a written price, which the app's own parser reads.
        for path in Paths.priceText {
            if let text = node.value(at: path)?.stringValue,
               let money = PriceParser.parse(text, currencyHint: currency) {
                return money
            }
        }
        return nil
    }

    private static func availability(in node: JSONValue) -> Availability {
        // Several services answer with a plain boolean.
        for path in Paths.inStockFlag {
            if case .some(.bool(let inStock)) = node.value(at: path) {
                return inStock ? .inStock : .outOfStock
            }
        }
        for path in Paths.availability {
            if let text = node.value(at: path)?.stringValue {
                let parsed = Availability.parse(text)
                if parsed != .unknown { return parsed }
            }
        }
        return .unknown
    }

    private static func firstString(in node: JSONValue, paths: [String]) -> String? {
        for path in paths {
            if let value = node.value(at: path)?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Candidate locations for each field, across the shapes these services
    /// actually return. Order is preference, not likelihood.
    private enum Paths {
        static let title = [
            "title", "name", "productTitle", "product_title",
            "product.title", "product.name", "data.title"
        ]
        static let priceValue = [
            "price.value", "price.amount", "price.current", "price",
            "currentPrice", "current_price", "priceAmount",
            "product.price.value", "product.price", "buybox_winner.price.value",
            "priceInfo.currentPrice.value", "offers.0.price"
        ]
        static let priceText = [
            "price.raw", "price.displayAmount", "price.formatted",
            "priceText", "price_string", "displayPrice",
            "product.price.raw", "price"
        ]
        static let currency = [
            "price.currency", "price.currencyCode", "currency",
            "priceCurrency", "product.price.currency"
        ]
        static let image = [
            "image", "imageUrl", "image_url", "thumbnailImage", "mainImage",
            "images.0", "images.0.link", "images.0.url", "images.0.large",
            "main_image.link", "product.main_image.link", "product.images.0",
            "galleryThumbnails.0"
        ]
        static let inStockFlag = ["inStock", "in_stock", "isAvailable", "available"]
        static let availability = [
            "availability", "availability.raw", "availabilityStatus",
            "stock", "stockStatus", "product.availability.raw"
        ]
        static let brand = [
            "brand", "brandName", "manufacturer",
            "product.brand", "byLineInfo.brand"
        ]
        static let description = [
            "description", "product.description", "features.0", "about.0"
        ]
    }
}

/// A local tally of how many requests have been spent this month.
///
/// These services meter their free allowances and go quiet or start charging
/// when one runs out. Counting locally is not billing, but it is enough to
/// answer "how much have I used?" without the user having to go and look.
nonisolated enum AmazonDataUsage {
    private static let countKey = "amazonData.monthCount"
    private static let periodKey = "amazonData.monthKey"

    static func recordRequest(defaults: UserDefaults = .standard) {
        let period = currentPeriod()
        if defaults.string(forKey: periodKey) != period {
            defaults.set(period, forKey: periodKey)
            defaults.set(0, forKey: countKey)
        }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static func requestsThisMonth(defaults: UserDefaults = .standard) -> Int {
        guard defaults.string(forKey: periodKey) == currentPeriod() else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.set(currentPeriod(), forKey: periodKey)
        defaults.set(0, forKey: countKey)
    }

    private static func currentPeriod() -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
