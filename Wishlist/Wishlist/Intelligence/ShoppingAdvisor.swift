//
//  ShoppingAdvisor.swift
//  Wishlist
//
//  The conversational half of the assistant: alternatives, whether a price
//  looks reasonable, what to check before buying.
//
//  This is deliberately a different contract from `ProductExtractor`. There,
//  the model reports facts about a page and every one is verified before the
//  app believes it. Here the model is giving advice, which cannot be verified
//  and is never written into an item — so instead the honesty is structural:
//  the model is told plainly what it cannot know, it is grounded in the data
//  the app actually observed, and the UI labels the whole conversation as
//  advice rather than product data.
//

import Foundation

nonisolated struct ShoppingAdvisor: Sendable {
    /// Roughly 150 words of answer, plus headroom.
    private static let replyTokens = 1024

    func reply(
        to turns: [ChatTurn],
        about item: WishlistItem?,
        budget: Money?,
        client: any LanguageModelClient
    ) async throws -> String? {
        try await client.reply(
            system: Self.systemPrompt(for: item, budget: budget),
            turns: turns,
            maxTokens: Self.replyTokens
        )
    }

    static func systemPrompt(for item: WishlistItem?, budget: Money?) -> String {
        var prompt = """
        You are a shopping adviser inside Wishlist, an app for saving things \
        someone wants to buy. Answer the way a knowledgeable friend would: \
        briefly, concretely, and without sales language.

        What you must not do:
        - You cannot browse the web and you cannot check any live price, \
        discount or stock level. Never say something is currently on sale, in \
        stock, or discontinued.
        - Never state a current price for a product. You may describe the rough \
        bracket something usually sits in, and when you do, say it needs \
        checking.
        - Never invent a model number, a specification or a retailer. If you are \
        not sure a product exists as described, say so.

        What good looks like:
        - When suggesting alternatives, name two to four, and say in a line what \
        makes each different — not just that it is "great".
        - When asked whether something is a good buy, reason from what the app \
        has actually observed, which is given below, and say what would change \
        your answer.
        - Prefer a short honest answer to a confident wrong one. Say "I'm not \
        sure" when you are not.
        - Keep replies under about 150 words unless asked for more. Short \
        paragraphs or a compact list.
        """

        if let item {
            prompt += "\n\n" + context(for: item)
        } else {
            prompt += "\n\nThe user has not opened this from a specific item, so ask what they are shopping for if it is not clear."
        }

        if let budget {
            prompt += "\n\nThe user has \(budget.formatted) available to spend. Take that into account without labouring it."
        }

        return prompt
    }

    /// Only fields the app genuinely holds. An absent value is simply omitted
    /// rather than described as unknown, which keeps the prompt short and
    /// stops the model treating "unknown" as a fact worth discussing.
    private static func context(for item: WishlistItem) -> String {
        var lines: [String] = ["The item being discussed, as recorded by the app:"]
        lines.append("- Name: \(item.fullName ?? item.displayName)")

        if let brand = item.brand { lines.append("- Brand: \(brand)") }
        if let retailer = item.displayRetailer { lines.append("- Store: \(retailer)") }
        if let category = item.category { lines.append("- Category: \(category)") }

        if let price = item.price {
            var line = "- Price the app last observed: \(price.formatted)"
            if let refreshed = item.dateRefreshed {
                line += " (checked \(DateText.friendly(refreshed)))"
            }
            lines.append(line)
        }
        if let original = item.originalPrice, item.priceChange != nil {
            lines.append("- Price when the user added it: \(original.formatted)")
        }
        if item.availability != .unknown {
            lines.append("- Availability the app last saw: \(item.availability.label)")
        }
        if let notes = item.notes, !notes.isEmpty {
            lines.append("- The user's own note: \(notes)")
        }
        lines.append("- Added to the wishlist \(DateText.friendly(item.dateAdded))")

        return lines.joined(separator: "\n")
    }

    /// One-tap openers, offered only when there is an item to talk about.
    /// A blank box is a worse question than a specific one.
    static func starters(for item: WishlistItem?) -> [String] {
        guard item != nil else { return [] }
        return [
            String(localized: "Suggest some alternatives"),
            String(localized: "Is this a good price?"),
            String(localized: "What should I check before buying?"),
            String(localized: "What do people usually complain about?")
        ]
    }
}
