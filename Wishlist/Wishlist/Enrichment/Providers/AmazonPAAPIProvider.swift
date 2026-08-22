//
//  AmazonPAAPIProvider.swift
//  Wishlist
//
//  Amazon's Product Advertising API v5. It is the authoritative source for
//  Amazon prices and availability, and it is the only one that stays correct
//  when Amazon changes its page markup — so when the user has Associates
//  credentials, it runs first for every Amazon link.
//
//  Requests are signed with AWS Signature Version 4. The secret key is read
//  from the Keychain for the duration of the call and never leaves the device
//  except inside the signature.
//

import Foundation
import CryptoKit

nonisolated struct AmazonPAAPIProvider: ProductDataProvider {
    let identifier = "amazon-paapi"
    let displayName = String(localized: "Amazon")
    let progressMessage = String(localized: "Looking up on Amazon…")
    let canProvidePrice = true

    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    private static let resources = [
        "Images.Primary.Large",
        "ItemInfo.Title",
        "ItemInfo.ByLineInfo",
        "ItemInfo.Features",
        "ItemInfo.Classifications",
        "Offers.Listings.Price",
        "Offers.Listings.Availability.Message",
        "Offers.Listings.Availability.Type",
        "Offers.Summaries.LowestPrice",
        "BrowseNodeInfo.BrowseNodes"
    ]

    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool {
        guard credentials.hasAmazonPAAPI else { return false }
        if request.link?.amazonASIN != nil { return true }
        // A plain search only makes sense when no link was given at all.
        return request.link == nil && request.searchTerm?.isEmpty == false
    }

    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot {
        let marketplace = request.link?.amazonMarketplace ?? credentials.amazonMarketplace

        if let asin = request.link?.amazonASIN {
            let body: [String: Any] = [
                "ItemIds": [asin],
                "ItemIdType": "ASIN",
                "Resources": Self.resources,
                "PartnerTag": credentials.amazonPartnerTag ?? "",
                "PartnerType": "Associates",
                "Marketplace": marketplace.rawValue
            ]
            let json = try await send(
                payload: try encode(body),
                operation: "GetItems",
                path: "/paapi5/getitems",
                marketplace: marketplace,
                credentials: credentials
            )
            guard let item = json.value(at: "ItemsResult.Items.0") else { throw LookupError.notFound }
            return snapshot(from: item, marketplace: marketplace)
        }

        guard let term = request.searchTerm, !term.isEmpty else { throw LookupError.noProductData }
        let body: [String: Any] = [
            "Keywords": term,
            "SearchIndex": "All",
            "ItemCount": 1,
            "Resources": Self.resources,
            "PartnerTag": credentials.amazonPartnerTag ?? "",
            "PartnerType": "Associates",
            "Marketplace": marketplace.rawValue
        ]
        let json = try await send(
            payload: try encode(body),
            operation: "SearchItems",
            path: "/paapi5/searchitems",
            marketplace: marketplace,
            credentials: credentials
        )
        guard let item = json.value(at: "SearchResult.Items.0") else { throw LookupError.notFound }
        return snapshot(from: item, marketplace: marketplace)
    }

    // MARK: - Request

    /// Serialised here so the request body crosses the async boundary as
    /// `Data` rather than an untyped dictionary.
    private func encode(_ body: [String: Any]) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        return data
    }

    private func send(
        payload: Data,
        operation: String,
        path: String,
        marketplace: AmazonMarketplace,
        credentials: LookupCredentials
    ) async throws -> JSONValue {
        guard let accessKey = credentials.amazonAccessKey,
              let secretKey = credentials.amazonSecretKey
        else { throw LookupError.notAuthorized(provider: displayName) }

        guard let url = URL(string: "https://\(marketplace.apiHost)\(path)") else {
            throw LookupError.providerUnavailable(provider: displayName)
        }

        let target = "com.amazon.paapi5.v1.ProductAdvertisingAPIv1." + operation
        let timestamp = Date()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("amz-1.0", forHTTPHeaderField: "content-encoding")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        request.setValue(marketplace.apiHost, forHTTPHeaderField: "host")
        request.setValue(Self.amzDate(timestamp), forHTTPHeaderField: "x-amz-date")
        request.setValue(target, forHTTPHeaderField: "x-amz-target")

        let authorization = Self.authorizationHeader(
            payload: payload,
            path: path,
            host: marketplace.apiHost,
            target: target,
            timestamp: timestamp,
            region: marketplace.signingRegion,
            accessKey: accessKey,
            secretKey: secretKey
        )
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let response = try await http.send(request, provider: displayName)
        guard let json = JSONValue.parse(response.data) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        if let error = json.value(at: "Errors.0") {
            throw Self.error(fromCode: error["Code"]?.stringValue, provider: displayName)
        }
        return json
    }

    private static func error(fromCode code: String?, provider: String) -> LookupError {
        switch code {
        case "InvalidSignature", "UnrecognizedClient", "AccessDenied", "InvalidPartnerTag":
            return .notAuthorized(provider: provider)
        case "TooManyRequests", "RequestThrottled":
            return .rateLimited(retryAfter: nil)
        case "ItemNotAccessible", "NoResults", "InvalidParameterValue":
            return .notFound
        default:
            return .providerUnavailable(provider: provider)
        }
    }

    // MARK: - Response mapping

    private func snapshot(from item: JSONValue, marketplace: AmazonMarketplace) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.sources = [displayName]
        snapshot.retailer = Retailer(name: "Amazon", domain: marketplace.domain)
        snapshot.name = item.value(at: "ItemInfo.Title.DisplayValue")?.stringValue

        if let imageString = item.value(at: "Images.Primary.Large.URL")?.stringValue
            ?? item.value(at: "Images.Primary.Medium.URL")?.stringValue {
            snapshot.imageURL = URL(string: imageString)
        }
        if let urlString = item["DetailPageURL"]?.stringValue {
            snapshot.productURL = URL(string: urlString)
        } else if let asin = item["ASIN"]?.stringValue {
            snapshot.productURL = URL(string: "https://\(marketplace.rawValue)/dp/\(asin)")
        }

        let listing = item.value(at: "Offers.Listings.0")
        if let amount = listing?.value(at: "Price.Amount")?.decimalValue, amount > 0 {
            let currency = listing?.value(at: "Price.Currency")?.stringValue ?? marketplace.currencyCode
            snapshot.price = Money(amount: amount, currencyCode: currency)
        } else if let amount = item.value(at: "Offers.Summaries.0.LowestPrice.Amount")?.decimalValue,
                  amount > 0 {
            let currency = item.value(at: "Offers.Summaries.0.LowestPrice.Currency")?.stringValue
                ?? marketplace.currencyCode
            snapshot.price = Money(amount: amount, currencyCode: currency)
        }

        snapshot.availability = Availability.parse(
            listing?.value(at: "Availability.Type")?.stringValue
                ?? listing?.value(at: "Availability.Message")?.stringValue
        )
        // A live listing with a price is in stock even when Amazon omits the
        // availability block entirely.
        if snapshot.availability == .unknown, snapshot.price != nil {
            snapshot.availability = .inStock
        }

        snapshot.brand = item.value(at: "ItemInfo.ByLineInfo.Brand.DisplayValue")?.stringValue
            ?? item.value(at: "ItemInfo.ByLineInfo.Manufacturer.DisplayValue")?.stringValue
        snapshot.category = item.value(at: "BrowseNodeInfo.BrowseNodes.0.ContextFreeName")?.stringValue
            ?? item.value(at: "BrowseNodeInfo.BrowseNodes.0.DisplayName")?.stringValue
            ?? item.value(at: "ItemInfo.Classifications.ProductGroup.DisplayValue")?.stringValue

        if let features = item.value(at: "ItemInfo.Features.DisplayValues")?.arrayValue
            .compactMap(\.stringValue), !features.isEmpty {
            snapshot.details = features.prefix(6).joined(separator: "\n• ")
            snapshot.details = "• " + (snapshot.details ?? "")
        }
        return snapshot
    }

    // MARK: - AWS Signature Version 4

    private static let signingAlgorithm = "AWS4-HMAC-SHA256"
    private static let service = "ProductAdvertisingAPI"
    private static let signedHeaders = "content-encoding;content-type;host;x-amz-date;x-amz-target"

    static func amzDate(_ date: Date) -> String {
        formatter(format: "yyyyMMdd'T'HHmmss'Z'").string(from: date)
    }

    static func dateStamp(_ date: Date) -> String {
        formatter(format: "yyyyMMdd").string(from: date)
    }

    private static func formatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    static func authorizationHeader(
        payload: Data,
        path: String,
        host: String,
        target: String,
        timestamp: Date,
        region: String,
        accessKey: String,
        secretKey: String
    ) -> String {
        let requestDate = amzDate(timestamp)
        let requestDay = dateStamp(timestamp)

        let canonicalHeaders = """
        content-encoding:amz-1.0
        content-type:application/json; charset=utf-8
        host:\(host)
        x-amz-date:\(requestDate)
        x-amz-target:\(target)

        """

        let canonicalRequest = [
            "POST",
            path,
            "",
            canonicalHeaders,
            signedHeaders,
            hexDigest(payload)
        ].joined(separator: "\n")

        let scope = "\(requestDay)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            signingAlgorithm,
            requestDate,
            scope,
            hexDigest(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        var key = Data(("AWS4" + secretKey).utf8)
        for component in [requestDay, region, service, "aws4_request"] {
            key = hmac(Data(component.utf8), key: key)
        }
        let signature = hexString(hmac(Data(stringToSign.utf8), key: key))

        return "\(signingAlgorithm) Credential=\(accessKey)/\(scope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private static func hmac(_ message: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func hexDigest(_ data: Data) -> String {
        hexString(Data(SHA256.hash(data: data)))
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
