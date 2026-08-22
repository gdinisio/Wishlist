//
//  MicrolinkProvider.swift
//  Wishlist
//
//  Some retailers refuse plain requests outright. Microlink renders the page
//  and hands back its metadata, which recovers a name and an image for links
//  the direct fetch could not read. It runs last, and only to fill gaps.
//

import Foundation

nonisolated struct MicrolinkProvider: ProductDataProvider {
    let identifier = "microlink"
    let displayName = String(localized: "Microlink")
    let progressMessage = String(localized: "Looking for missing details…")
    let canProvidePrice = false

    private let http: HTTPClient
    private let endpoint = URL(string: "https://api.microlink.io")!

    init(http: HTTPClient) {
        self.http = http
    }

    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool {
        request.link != nil
    }

    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot {
        guard let link = request.link else { throw LookupError.noProductData }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: link.canonicalURL.absoluteString),
            URLQueryItem(name: "meta", value: "true")
        ]
        guard let url = components.url else {
            throw LookupError.providerUnavailable(provider: displayName)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = credentials.microlinkKey, !key.isEmpty {
            urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        }

        let response = try await http.send(urlRequest, provider: displayName)
        guard let json = JSONValue.parse(response.data),
              json["status"]?.stringValue == "success",
              let payload = json["data"]
        else { throw LookupError.noProductData }

        var snapshot = ProductSnapshot()
        snapshot.sources = [displayName]
        snapshot.name = StructuredDataParser.cleanedTitle(
            payload["title"]?.stringValue,
            retailer: payload["publisher"]?.stringValue
        )
        if let imageString = payload.value(at: "image.url")?.stringValue
            ?? payload.value(at: "logo.url")?.stringValue {
            snapshot.imageURL = URL(string: imageString)
        }
        if let description = payload["description"]?.stringValue {
            snapshot.details = HTMLParser.plainText(from: description)
        }
        if let publisher = payload["publisher"]?.stringValue {
            snapshot.retailer = Retailer(name: publisher, domain: link.host)
        }
        snapshot.productURL = link.canonicalURL

        guard !snapshot.isEmpty else { throw LookupError.noProductData }
        return snapshot
    }
}
