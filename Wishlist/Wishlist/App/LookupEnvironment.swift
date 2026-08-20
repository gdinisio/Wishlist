//
//  LookupEnvironment.swift
//  Wishlist
//
//  The lookup pipeline handed to views through the environment, so the Add
//  flow depends on the protocol-driven service rather than reaching for a
//  singleton.
//

import SwiftUI
import Foundation
import Observation

private nonisolated struct ProductLookupKey: EnvironmentKey {
    static let defaultValue: ProductLookupService = .makeDefault()
}

extension EnvironmentValues {
    nonisolated var productLookup: ProductLookupService {
        get { self[ProductLookupKey.self] }
        set { self[ProductLookupKey.self] = newValue }
    }
}

/// Carries the current stage of a lookup from the pipeline (which runs off the
/// main actor) to the view, without the view having to capture itself.
@Observable
@MainActor
final class LookupProgress {
    var message: String?
}
