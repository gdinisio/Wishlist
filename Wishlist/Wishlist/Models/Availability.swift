//
//  Availability.swift
//  Wishlist
//

import Foundation

/// Normalised stock status.
///
/// Every case carries a symbol *and* a label so status is never communicated by
/// colour alone (HIG: accessibility, and colour is not information).
nonisolated enum Availability: String, Codable, CaseIterable, Sendable {
    case inStock
    case outOfStock
    case preOrder
    case limited
    case discontinued
    case unknown

    var label: String {
        switch self {
        case .inStock: String(localized: "In Stock")
        case .outOfStock: String(localized: "Out of Stock")
        case .preOrder: String(localized: "Pre-order")
        case .limited: String(localized: "Low Stock")
        case .discontinued: String(localized: "Discontinued")
        case .unknown: String(localized: "Availability Unknown")
        }
    }

    var symbolName: String {
        switch self {
        case .inStock: "checkmark.circle.fill"
        case .outOfStock: "xmark.circle.fill"
        case .preOrder: "clock.fill"
        case .limited: "exclamationmark.circle.fill"
        case .discontinued: "minus.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// Whether this status is worth drawing attention to in a dense list row.
    var isNoteworthy: Bool {
        switch self {
        case .outOfStock, .limited, .preOrder, .discontinued: true
        case .inStock, .unknown: false
        }
    }
}

nonisolated extension Availability {
    /// Best-effort normalisation of the free-text availability strings used by
    /// schema.org, Amazon and most retailer APIs. Unrecognised input stays
    /// `.unknown` rather than being guessed at.
    static func parse(_ raw: String?) -> Availability {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return .unknown }

        // schema.org URLs, e.g. "https://schema.org/InStock"
        let token = raw.split(separator: "/").last.map(String.init) ?? raw

        if token.contains("backorder") || token.contains("preorder") || token.contains("pre-order") {
            return .preOrder
        }
        if token.contains("discontinued") {
            return .discontinued
        }
        if token.contains("outofstock") || token.contains("out of stock")
            || token.contains("sold out") || token.contains("soldout")
            || token.contains("unavailable") {
            return .outOfStock
        }
        if token.contains("limited") || token.contains("low stock")
            || token.contains("only ") || token.contains("left in stock") {
            return .limited
        }
        if token.contains("instock") || token.contains("in stock")
            || token.contains("available") || token.contains("onlineonly") {
            return .inStock
        }
        return .unknown
    }
}
