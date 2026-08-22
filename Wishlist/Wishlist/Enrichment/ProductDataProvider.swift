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

/// Why a lookup is running. Adding an item wants everything; re-checking one
/// already on the list wants a price and nothing else — and should not spend a
/// third-party call, or a language model, on a picture it already has.
nonisolated enum LookupPurpose: Sendable, Hashable {
    case full
    case priceCheck

    /// How long the whole chain may spend before returning what it has. Each
    /// request already has its own timeout; this stops four of them in a row
    /// adding up to a minute of waiting.
    var budget: TimeInterval {
        switch self {
        case .full: 20
        case .priceCheck: 12
        }
    }
}

/// What the user asked to look up: a link, a plain product name, or both.
nonisolated struct LookupRequest: Sendable, Hashable {
    var link: ProductLink?
    var searchTerm: String?
    var purpose: LookupPurpose = .full
    /// A page body already downloaded while resolving a shortened link, passed
    /// along so the chain never fetches the same page twice.
    var prefetchedPage: PrefetchedPage?

    var isEmpty: Bool { link == nil && (searchTerm?.isEmpty ?? true) }

    /// Stable key used to collapse duplicate in-flight lookups. The purpose is
    /// part of it: a price check and a full lookup want different work done.
    var coalescingKey: String {
        let scope = purpose == .priceCheck ? "price" : "full"
        if let link { return scope + ":link:" + link.canonicalURL.absoluteString }
        return scope + ":term:" + (searchTerm ?? "").lowercased()
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
    var microlinkKey: String?
    /// Reading the product page directly needs no key, so it is on by default.
    var allowsWebPageLookup: Bool = true
    /// Optional language-model assistance. Off unless the user turns it on.
    var intelligence: IntelligenceSettings = IntelligenceSettings()
    /// Optional third-party Amazon reader. Off unless the user turns it on.
    var amazonData: AmazonDataSettings = AmazonDataSettings()

    var hasAmazonPAAPI: Bool {
        isPresent(amazonAccessKey) && isPresent(amazonSecretKey) && isPresent(amazonPartnerTag)
    }

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
    /// Whether this provider can ever return a price. One that cannot is
    /// skipped entirely when the chain is only re-checking a price, rather than
    /// being called and found unhelpful every time.
    var canProvidePrice: Bool { get }
    /// Whether this provider can attempt the request at all.
    func canHandle(_ request: LookupRequest, credentials: LookupCredentials) -> Bool
    /// Perform the lookup. Throws `LookupError`, never a transport error.
    func fetch(_ request: LookupRequest, credentials: LookupCredentials) async throws -> ProductSnapshot
}
