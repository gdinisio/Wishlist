//
//  Wishlist.swift
//  Wishlist
//
//  A named list — "Tech", "Back to School", "Kitchen".
//
//  Collections were derived from the items that named them, which meant a list
//  could not exist until something was already in it. That is backwards: people
//  decide they want a "Back to School" list and *then* fill it. So a wishlist
//  is a stored thing of its own, and an item points at one.
//

import Foundation

nonisolated struct Wishlist: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    /// An SF Symbol, the way Reminders marks its lists apart.
    var symbolName: String
    var dateCreated: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = Wishlist.defaultSymbol,
        dateCreated: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.dateCreated = dateCreated
    }

    static let defaultSymbol = "star"

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled List") : trimmed
    }

    /// A small, deliberate set. A symbol picker with a thousand options is a
    /// search problem; twenty recognisable ones is a choice.
    static let symbolChoices = [
        "star", "gift", "laptopcomputer", "iphone", "headphones", "gamecontroller",
        "book", "graduationcap", "tshirt", "shoe", "bag", "house",
        "fork.knife", "bicycle", "car", "camera", "paintbrush", "guitars",
        "dumbbell", "pawprint", "leaf", "birthday.cake", "hammer", "sparkles"
    ]
}
