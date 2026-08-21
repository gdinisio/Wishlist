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

    /// Injectable pieces are optional rather than defaulted: a default
    /// parameter value is evaluated in a nonisolated context, so a main-actor
    /// type cannot be constructed there. Building them in the body — which is
    /// main-actor isolated — keeps the same call sites working.
    init(
        settings: SettingsStore? = nil,
        store: (any WishlistPersisting)? = nil,
        lookup: ProductLookupService? = nil,
        network: NetworkMonitor? = nil
    ) {
        let resolvedSettings = settings ?? SettingsStore()
        let resolvedLookup = lookup ?? ProductLookupService.makeDefault()

        self.settings = resolvedSettings
        self.network = network ?? NetworkMonitor()
        self.lookup = resolvedLookup
        self.repository = WishlistRepository(
            store: store ?? FileWishlistStore(),
            lookup: resolvedLookup,
            credentialsProvider: { resolvedSettings.credentials }
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
