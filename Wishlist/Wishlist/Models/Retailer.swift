//
//  Retailer.swift
//  Wishlist
//

import Foundation

/// The store an item comes from. Kept as a small value type rather than a bare
/// string so the domain travels with the display name (used for duplicate
/// detection and for choosing a lookup provider).
nonisolated struct Retailer: Hashable, Codable, Sendable {
    var name: String
    var domain: String?

    init(name: String, domain: String? = nil) {
        self.name = name
        self.domain = domain?.lowercased()
    }

    /// True when this retailer is one of Amazon's marketplaces.
    var isAmazon: Bool {
        guard let domain else { return name.localizedCaseInsensitiveContains("amazon") }
        return domain.contains("amazon.")
    }
}
