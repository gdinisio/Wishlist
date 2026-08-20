//
//  PricePoint.swift
//  Wishlist
//

import Foundation

/// A price observed at a moment in time. Recorded only when Wishlist actually
/// retrieved a price, so the history is a record of observations — never an
/// estimate or an interpolation.
nonisolated struct PricePoint: Hashable, Codable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var price: Money

    init(id: UUID = UUID(), date: Date = .now, price: Money) {
        self.id = id
        self.date = date
        self.price = price
    }
}
