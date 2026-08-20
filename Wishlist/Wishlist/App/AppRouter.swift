//
//  AppRouter.swift
//  Wishlist
//
//  Cross-screen navigation that would otherwise need bindings threaded through
//  four levels of view: which tab is showing, and the ability for a flow to
//  send the user somewhere useful.
//

import Foundation
import Observation

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .wishlist

    func showSettings() {
        selectedTab = .settings
    }
}
