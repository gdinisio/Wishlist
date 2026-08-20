//
//  ProductDataProvider.swift
//  Wishlist
//
//  The seam that keeps the app independent of any one product API. A provider
//  takes a validated request plus whatever credentials the user has saved, and
//  returns a normalised snapshot — or throws a `LookupError`. Adding a new
//  source is a matter of writing one of these and listing it in the chain.
//

import Foundation

/// What the user asked to look up: a link, a plain product name, or both.
nonisolated struct LookupRequest: Sendable, Hashable {
    var link: ProductLink?
    var searchTerm: String?
    /// A page body already downloaded while resolving a shortened link, passed
    /// along so the chain never fetches the same page twice.
    var prefetchedPage: PrefetchedPage?

    var isEmpty: Bool { link == nil && (searchTerm?.isEmpty ?? true) }

    /// Stable key used to collapse duplicate in-flight lookups.
    var coalescingKey: String {
        if let link { return "link:" + link.canonicalURL.absoluteString }
        return "term:" + (searchTerm ?? "").lowercased()
    }
}

/// Credentials and lookup preferences, snapshotted at the moment of the
/// request. Providers never reach into app settings themselves, which keeps
/// them trivially testable.
nonisolated struct LookupCredentials: Sendable, Equatable {
    var amazonAccessKey: String?
    var amazonSecretKey: String?
    var amazonPartnerTag: String?
    var amazonMarketplace: AmazonMarketplace = .unitedKingdom
    var rainforestKey: String?
    var microlinkKey: String?
    /// Reading the product page directly needs no key, so it is on by default.
    var allowsWebPageLookup: Bool = true

    var hasAmazonPAAPI: Bool {
        isPresent(amazonAccessKey) && isPresent(amazonSecretKey) && isPresent(amazonPartnerTag)
    }

    var hasRainforest: Bool { isPresent(rainforestKey) }

    private func isPresent(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated protocol ProductDataProvider: Sendable {
    /// Stable identifier used in settings and logs.
    var identifier: String { get }
    /// Name shown to the user, e.g. on the "Found on…" line.
    var displayName: String { get }
    /// Present-tense sentence shown while this provider is being consulted.
    var progressMessage: String { get }
    /// Whether this provider can attempt the request at all.
    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool
    /// Perform the lookup. Throws `LookupError`, never a transport error.
    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot
}
