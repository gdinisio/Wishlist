//
//  FileWishlistStore.swift
//  Wishlist
//
//  Local persistence: one JSON document in Application Support, written
//  atomically off the main thread. Small enough to load instantly, structured
//  enough to sync later.
//

import Foundation
import OSLog

actor FileWishlistStore: WishlistPersisting {
    private let fileURL: URL
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "persistence")

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL.documentsDirectory
            self.fileURL = base
                .appendingPathComponent("Wishlist", isDirectory: true)
                .appendingPathComponent("wishlist.json")
        }
    }

    func load() async throws -> WishlistArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return WishlistArchive(items: [])
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return WishlistArchive(items: []) }
        do {
            return try WishlistCoder.makeDecoder().decode(WishlistArchive.self, from: data)
        } catch {
            // A corrupt file must never present as an empty wishlist: keep a
            // copy so nothing is lost, and surface the failure.
            log.error("Wishlist archive could not be decoded: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(
                at: fileURL,
                to: fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            )
            throw error
        }
    }

    func save(_ archive: WishlistArchive) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try WishlistCoder.makeEncoder().encode(archive)
        // `.atomic` writes to a temporary file and renames, so an interrupted
        // save can never leave a half-written wishlist behind.
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Used by previews and tests. Same contract, no disk.
actor InMemoryWishlistStore: WishlistPersisting {
    private var archive: WishlistArchive

    init(items: [WishlistItem] = [], wishlists: [Wishlist] = []) {
        self.archive = WishlistArchive(items: items, wishlists: wishlists)
    }

    func load() async throws -> WishlistArchive { archive }

    func save(_ archive: WishlistArchive) async throws { self.archive = archive }
}
