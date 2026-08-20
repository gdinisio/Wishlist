//
//  RootView.swift
//  Wishlist
//
//  Three tabs, three questions answered without a tap: what do I want, what
//  did I get, and how is this set up.
//

import SwiftUI
import Foundation

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(String(localized: "Wishlist"), systemImage: "list.star", value: AppTab.wishlist) {
                WishlistScreen()
            }

            Tab(String(localized: "Obtained"), systemImage: "checkmark.circle", value: AppTab.obtained) {
                ObtainedScreen()
            }

            Tab(String(localized: "Settings"), systemImage: "gearshape", value: AppTab.settings) {
                SettingsScreen()
            }
        }
    }
}

nonisolated enum AppTab: Hashable {
    case wishlist
    case obtained
    case settings
}

#Preview {
    RootView().withPreviewEnvironment()
}
