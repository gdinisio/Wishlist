//
//  AmazonDataService.swift
//  Wishlist
//
//  A third-party reader for Amazon product data.
//
//  Amazon's own Product Advertising API is free but gated behind an Associates
//  account with tax identity and qualifying sales. Reading the product page
//  works without any of that, but Amazon serves a human check often enough to
//  be annoying. This sits between the two: a commercial reader the user brings
//  their own key to.
//
//  No single service is hard-coded, for two reasons. Their response shapes
//  differ, and their terms change — this app has already been broken once by a
//  provider retiring something out from under it. So a service is described
//  rather than implemented, every field is read through a list of candidate
//  paths rather than one, and a custom endpoint is a first-class option.
//

import Foundation

nonisolated enum AmazonDataService: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case apify
    case hasData
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .apify: "Apify"
        case .hasData: "HasData"
        case .custom: String(localized: "Custom")
        }
    }

    /// Where to sign up, shown in Settings so the user is never left guessing
    /// which of a dozen similar services this expects.
    var signupHost: String? {
        switch self {
        case .off, .custom: nil
        case .apify: "apify.com"
        case .hasData: "hasdata.com"
        }
    }

    var explanation: String {
        switch self {
        case .off:
            String(localized: "Amazon links are read from the product page, which needs no key.")
        case .apify:
            String(localized: "Runs a scraper you choose and returns its result. Reported to include a monthly free allowance that renews, which is why it is offered first — check the current terms yourself before relying on it.")
        case .hasData:
            String(localized: "A direct product endpoint. Its free allowance has been advertised as a one-off trial rather than a renewing monthly amount, so expect it to run out.")
        case .custom:
            String(localized: "Any service with a URL you can construct. Put your key in the address itself.")
        }
    }

    /// Whether this service needs an API key of its own.
    var needsKey: Bool {
        switch self {
        case .off, .custom: false
        case .apify, .hasData: true
        }
    }

    /// Apify runs a named actor rather than a fixed endpoint.
    var needsActorIdentifier: Bool { self == .apify }

    var needsTemplate: Bool { self == .custom }
}

/// Everything the user configured for the third-party reader.
nonisolated struct AmazonDataSettings: Sendable, Equatable {
    var service: AmazonDataService = .off
    var apiKey: String?
    /// Apify actor, in `username~actor-name` form.
    var actorIdentifier: String = AmazonDataSettings.defaultActor
    /// Custom endpoint, with `{asin}` and `{domain}` placeholders.
    var urlTemplate: String = ""
    /// Whether routine price refreshes may spend credits. Off keeps the
    /// allowance for adding items, where accuracy matters most.
    var usedForRefreshes: Bool = true

    static let defaultActor = "junglee~amazon-product-scraper"

    var isConfigured: Bool {
        switch service {
        case .off:
            return false
        case .custom:
            return urlTemplate.contains("{asin}")
        case .apify:
            return hasKey && !actorIdentifier.trimmingCharacters(in: .whitespaces).isEmpty
        case .hasData:
            return hasKey
        }
    }

    private var hasKey: Bool {
        !(apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
