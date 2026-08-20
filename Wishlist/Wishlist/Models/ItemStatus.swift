//
//  ItemStatus.swift
//  Wishlist
//

import Foundation

/// Where an item sits in its lifecycle. Obtaining an item never deletes it —
/// it moves between these two states so the history is preserved.
nonisolated enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case active
    case obtained

    var label: String {
        switch self {
        case .active: String(localized: "On Wishlist")
        case .obtained: String(localized: "Obtained")
        }
    }

    var symbolName: String {
        switch self {
        case .active: "star"
        case .obtained: "checkmark.circle.fill"
        }
    }
}
