//
//  WishlistApp.swift
//  Wishlist
//
//  Created by Giovanni Di Nisio on 20/08/2026.
//

import SwiftUI
import Foundation

@main
struct WishlistApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.repository)
                .environment(environment.settings)
                .environment(environment.network)
                .environment(environment.router)
                .environment(\.productLookup, environment.lookup)
                .task {
                    await environment.repository.load()
                    await refreshIfAppropriate()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Leaving the foreground is the last reliable moment to
                    // write: never rely on a debounce timer to survive it.
                    if phase != .active {
                        environment.settings.persistNow()
                        Task { await environment.repository.saveNow() }
                    }
                }
        }
    }

    /// A quiet refresh on launch keeps prices current without the user asking,
    /// but only when it can actually succeed.
    private func refreshIfAppropriate() async {
        guard environment.settings.refreshOnLaunch,
              environment.network.isOnline,
              !environment.repository.activeItems.isEmpty
        else { return }
        await environment.repository.refreshPrices()
    }
}
