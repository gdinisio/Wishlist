//
//  WishlistPersisting.swift
//  Wishlist
//
//  The persistence seam. The repository knows only this protocol, so the local
//  file store can later be joined — or replaced — by a CloudKit-backed store
//  without touching a single view.
//

import Foundation

nonisolated protocol WishlistPersisting: Sendable {
    func load() async throws -> [WishlistItem]
    func save(_ items: [WishlistItem]) async throws
}

/// Versioned envelope written to disk. Storing a schema version now means a
/// future format change — or a sync layer that needs a device identifier — is
/// a migration rather than a data loss.
nonisolated struct WishlistArchive: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var items: [WishlistItem]
    var savedAt: Date

    init(items: [WishlistItem], savedAt: Date = .now) {
        self.version = Self.currentVersion
        self.items = items
        self.savedAt = savedAt
    }
}

nonisolated enum WishlistCoder {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
