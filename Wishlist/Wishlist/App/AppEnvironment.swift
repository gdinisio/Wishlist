//
//  AppEnvironment.swift
//  Wishlist
//
//  Composition root. Every dependency is created here and handed down, so the
//  network layer and the store can be swapped for test doubles without a view
//  knowing anything changed.
//

import Foundation
import Observation

@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let network: NetworkMonitor
    let lookup: ProductLookupService
    let repository: WishlistRepository
    let router = AppRouter()
    let alerts = PriceAlertCenter()

    init(
        settings: SettingsStore = SettingsStore(),
        store: (any WishlistPersisting)? = nil,
        lookup: ProductLookupService = .makeDefault(),
        network: NetworkMonitor = NetworkMonitor()
    ) {
        self.settings = settings
        self.network = network
        self.lookup = lookup
        self.repository = WishlistRepository(
            store: store ?? FileWishlistStore(),
            lookup: lookup,
            credentialsProvider: { settings.credentials }
        )
    }

    /// A fully in-memory environment for SwiftUI previews.
    static func preview(items: [WishlistItem] = WishlistItem.samples) -> AppEnvironment {
        let environment = AppEnvironment(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            store: InMemoryWishlistStore(items: items)
        )
        return environment
    }
}
