//
//  ProductExtractor.swift
//  Wishlist
//
//  The last resort for a page no parser could read. Retailers that publish no
//  structured data and no recognisable markup still show a human a name and a
//  price — so the page's text is handed to a language model whose only job is
//  to point at where those values are.
//
//  The model copies; this file interprets. It is asked for the price *as
//  written* rather than for a number, and for the shop's own words about stock
//  rather than for a verdict, so that parsing and judgement stay in code that
//  can be reasoned about — and every answer is checked back against the page
//  before it is believed.
//

import Foundation
import OSLog

nonisolated struct ProductExtractor: Sendable {
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "intelligence")

    private static let system = """
    You locate product details that are already written on a retail web page.

    Rules:
    - Copy values exactly as they appear. Do not reformat, tidy, translate or \
    round anything.
    - Never estimate, infer or calculate a value. If the page does not state \
    something, return an empty string for it.
    - Report only the main product the page is about. Ignore adverts, \
    recommendations, related items, reviews and delivery messages.
    """

    private static let function = LanguageModelFunction(
        name: "record_product",
        purpose: "Record the product details stated on the page.",
        schema: [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "The product's name, copied exactly from the page. Empty string if absent."
                ],
                "priceText": [
                    "type": "string",
                    "description": "The current price exactly as written, including its currency symbol, for example \"£249.00\". Not a list price, not a discount, not a monthly instalment. Empty string if the page shows no price."
                ],
                "currencyCode": [
                    "type": "string",
                    "description": "ISO 4217 code only if the page states one, for example \"GBP\". Empty string otherwise."
                ],
                "brand": [
                    "type": "string",
                    "description": "The brand or manufacturer as written on the page. Empty string if absent."
                ],
                "availabilityText": [
                    "type": "string",
                    "description": "The page's own words about stock, for example \"In stock\" or \"Currently unavailable\". Empty string if the page does not say."
                ],
                "productDescription": [
                    "type": "string",
                    "description": "One short sentence about the product, copied from the page. Empty string if absent."
                ]
            ],
            "required": [
                "name", "priceText", "currencyCode", "brand",
                "availabilityText", "productDescription"
            ],
            "additionalProperties": false
        ]
    )

    /// Reads a page that the structured parsers could not. Returns an empty
    /// snapshot rather than throwing: this is an enhancement, and a failure
    /// here must never fail the lookup.
    func snapshot(
        fromPageText digest: String,
        link: ProductLink,
        client: any LanguageModelClient
    ) async -> ProductSnapshot {
        guard digest.count > 200 else { return ProductSnapshot() }

        let prompt = """
        Product page: \(link.canonicalURL.absoluteString)

        Page text:
        \(digest)
        """

        let answer: JSONValue?
        do {
            answer = try await client.answer(
                system: Self.system,
                prompt: prompt,
                function: Self.function,
                maxTokens: 1024
            )
        } catch {
            log.notice("Model extraction failed: \(String(describing: error), privacy: .public)")
            return ProductSnapshot()
        }
        guard let answer else { return ProductSnapshot() }

        return verified(answer, against: digest, link: link, modelName: client.displayName)
    }

    /// Accepts only what the page itself supports.
    private func verified(
        _ answer: JSONValue,
        against digest: String,
        link: ProductLink,
        modelName: String
    ) -> ProductSnapshot {
        var snapshot = ProductSnapshot()
        snapshot.retailer = link.retailer
        snapshot.productURL = link.canonicalURL

        if let name = answer["name"]?.stringValue, SourceCheck.isSupportedName(name, by: digest) {
            snapshot.name = name
        }

        if let priceText = answer["priceText"]?.stringValue,
           SourceCheck.isSupportedPrice(priceText, by: digest) {
            let stated = answer["currencyCode"]?.stringValue
            let hint = isPlausibleCurrencyCode(stated) ? stated : link.currencyHint
            snapshot.price = PriceParser.parse(priceText, currencyHint: hint)
        }

        if let brand = answer["brand"]?.stringValue, SourceCheck.contains(brand, in: digest) {
            snapshot.brand = brand
        }

        // The model finds the sentence; the app decides what it means.
        if let availabilityText = answer["availabilityText"]?.stringValue,
           SourceCheck.contains(availabilityText, in: digest) {
            snapshot.availability = Availability.parse(availabilityText)
        }

        if let details = answer["productDescription"]?.stringValue,
           SourceCheck.contains(details, in: digest) {
            snapshot.details = details
        }

        if !snapshot.isEmpty { snapshot.sources = [modelName] }
        return snapshot
    }

    private func isPlausibleCurrencyCode(_ code: String?) -> Bool {
        guard let code, code.count == 3 else { return false }
        return code.allSatisfy { $0.isLetter && $0.isASCII }
    }
}
