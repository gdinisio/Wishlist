//
//  SnapshotPolisher.swift
//  Wishlist
//
//  Retailers write titles for search engines: "Sony WH-1000XM5 Wireless
//  Industry Leading Noise Canceling Headphones with Auto Noise Canceling
//  Optimizer, Crystal Clear Hands-Free Calling, and Alexa Voice Control, Black".
//  That is four lines in a list row and nothing a person would ever say.
//
//  This shortens the title using only words the title already contains — the
//  result is verified word by word — and suggests a category from a fixed list
//  when the retailer published none. The full title is kept and shown on the
//  item's own screen, so nothing is lost.
//

import Foundation
import OSLog

nonisolated struct SnapshotPolisher: Sendable {
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "intelligence")

    /// Titles longer than this are worth shortening; shorter ones are left be.
    private static let longTitleThreshold = 60

    static let categories: [String] = [
        "Audio", "Cameras", "Computers", "Phones & Accessories", "Electronics",
        "Home & Kitchen", "Furniture", "Garden & Outdoor", "Tools & DIY",
        "Clothing", "Shoes", "Bags & Accessories", "Jewellery & Watches",
        "Beauty & Grooming", "Health & Fitness", "Sports & Outdoors",
        "Toys & Games", "Video Games", "Books", "Music & Instruments",
        "Stationery & Office", "Pet Supplies", "Food & Drink", "Baby & Kids",
        "Car & Motorbike", "Other"
    ]

    private static let system = """
    You tidy product titles for a personal shopping list.

    Rules:
    - Use only words that already appear in the given title. Never add a word, \
    a number, a colour or a detail that is not there.
    - Keep the brand and the model or product name. Drop marketing phrases, \
    feature lists and repeated keywords.
    - Aim for something a person would say out loud, usually two to six words.
    """

    private static func function(includeTitle: Bool, includeCategory: Bool) -> LanguageModelFunction {
        var properties: [String: JSONValue] = [:]
        var required: [JSONValue] = []

        if includeTitle {
            properties["shortTitle"] = [
                "type": "string",
                "description": "The title shortened using only words already present in it. Empty string if it is already short enough."
            ]
            required.append("shortTitle")
        }
        if includeCategory {
            properties["category"] = [
                "type": "string",
                "description": "The single best category for this product.",
                "enum": .array(categories.map { .string($0) })
            ]
            required.append("category")
        }

        return LanguageModelFunction(
            name: "tidy_product",
            purpose: "Shorten a product title and categorise the product.",
            schema: [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required),
                "additionalProperties": false
            ]
        )
    }

    /// Returns the snapshot unchanged unless there is something worth doing and
    /// the model's answer survives verification.
    func polished(
        _ snapshot: ProductSnapshot,
        settings: IntelligenceSettings,
        client: any LanguageModelClient
    ) async -> ProductSnapshot {
        guard let name = snapshot.name, !name.isEmpty else { return snapshot }

        let wantsTitle = settings.shortensTitles && name.count > Self.longTitleThreshold
        let wantsCategory = settings.suggestsCategories
            && (snapshot.category?.isEmpty ?? true)
        guard wantsTitle || wantsCategory else { return snapshot }

        var prompt = "Title: \(name)"
        if let brand = snapshot.brand { prompt += "\nBrand: \(brand)" }
        if let retailer = snapshot.retailer?.name { prompt += "\nStore: \(retailer)" }

        let answer: JSONValue?
        do {
            answer = try await client.answer(
                system: Self.system,
                prompt: prompt,
                function: Self.function(includeTitle: wantsTitle, includeCategory: wantsCategory),
                maxTokens: 256
            )
        } catch {
            log.notice("Model tidy-up failed: \(String(describing: error), privacy: .public)")
            return snapshot
        }
        guard let answer else { return snapshot }

        var result = snapshot

        if wantsTitle,
           let short = answer["shortTitle"]?.stringValue,
           Self.isFaithfulShortening(short, of: name) {
            result.fullName = name
            result.name = short
        }

        if wantsCategory,
           let category = answer["category"]?.stringValue,
           Self.categories.contains(category),
           category != "Other" {
            result.category = category
        }

        return result
    }

    /// A shortened title may only ever be a subset of the original's words.
    /// Anything else is the model writing rather than trimming.
    static func isFaithfulShortening(_ short: String, of original: String) -> Bool {
        let trimmed = short.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < original.count else { return false }

        let originalWords = Set(
            SourceCheck.normalised(original)
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
        let shortWords = SourceCheck.normalised(trimmed)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        guard !shortWords.isEmpty else { return false }
        return shortWords.allSatisfy { originalWords.contains($0) }
    }
}
