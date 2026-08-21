//
//  LookupError.swift
//  Wishlist
//
//  Every failure the lookup pipeline can produce, expressed in the user's
//  language. Raw API errors and status codes are logged, never surfaced.
//

import Foundation

nonisolated enum LookupError: Error, Equatable, Sendable {
    /// The text the user typed is not a usable web address.
    case invalidURL
    /// A valid address, but not one we can read product data from.
    case unsupportedURL(host: String?)
    /// The device has no network connection.
    case offline
    /// The request took too long.
    case timedOut
    /// The provider asked us to slow down.
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider rejected our credentials.
    case notAuthorized(provider: String)
    /// The page or product does not exist.
    case notFound
    /// The provider answered, but with nothing we could use.
    case noProductData
    /// The service answered with a refusal it explained itself — a bad model
    /// name, a malformed request, a plan limit. `detail` is the service's own
    /// wording, which is nearly always more useful than ours.
    case providerRejected(provider: String, detail: String?)
    /// Anything else: transport failures, malformed responses, 5xx.
    case providerUnavailable(provider: String?)
    /// No provider is able to handle this request at all.
    case noProviderConfigured
    /// The user cancelled.
    case cancelled
}

nonisolated extension LookupError {
    /// Short, sentence-case title suitable for an inline message or an alert.
    var title: String {
        switch self {
        case .invalidURL: String(localized: "That doesn’t look like a link")
        case .unsupportedURL: String(localized: "Can’t read this link")
        case .offline: String(localized: "No Internet Connection")
        case .timedOut: String(localized: "Taking too long")
        case .rateLimited: String(localized: "Too many requests")
        case .notAuthorized: String(localized: "Check your API key")
        case .notFound: String(localized: "Product not found")
        case .noProductData: String(localized: "No details found")
        case .providerRejected(let provider, _): String(localized: "\(provider) refused the request")
        case .providerUnavailable: String(localized: "Lookup unavailable")
        case .noProviderConfigured: String(localized: "No lookup service available")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    /// One plain sentence explaining what to do next.
    var guidance: String {
        switch self {
        case .invalidURL:
            return String(localized: "Paste the full web address of the product, or add the item by name instead.")
        case .unsupportedURL(let host):
            if let host {
                return String(localized: "Wishlist couldn’t read product details from \(host). You can still add the item and fill in the details yourself.")
            }
            return String(localized: "Wishlist couldn’t read product details from this site. You can still add the item and fill in the details yourself.")
        case .offline:
            return String(localized: "Connect to Wi‑Fi or mobile data to look up product details. You can add the item now and refresh it later.")
        case .timedOut:
            return String(localized: "The store didn’t respond in time. Try again, or add the item and refresh it later.")
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 1 {
                return String(localized: "The lookup service is busy. Try again in about \(Int(retryAfter.rounded())) seconds.")
            }
            return String(localized: "The lookup service is busy. Wait a moment and try again.")
        case .notAuthorized(let provider):
            return String(localized: "\(provider) didn’t accept the key saved in Settings. Check that it’s correct and still active.")
        case .notFound:
            return String(localized: "This product may have been removed, or the link may have expired.")
        case .noProductData:
            return String(localized: "The page didn’t include product information Wishlist can read. Add the item and fill in what you know.")
        case .providerRejected(_, let detail):
            if let detail, !detail.isEmpty {
                return detail
            }
            return String(localized: "The service understood the request but would not carry it out. Check the settings for it.")
        case .providerUnavailable:
            return String(localized: "The store or lookup service isn’t responding right now. Try again in a moment.")
        case .noProviderConfigured:
            return String(localized: "Add an API key in Settings to look up prices, or add the item by name.")
        case .cancelled:
            return String(localized: "The lookup was cancelled.")
        }
    }

    var symbolName: String {
        switch self {
        case .invalidURL, .unsupportedURL: "link.badge.plus"
        case .offline: "wifi.slash"
        case .timedOut: "clock.badge.exclamationmark"
        case .rateLimited: "hourglass"
        case .notAuthorized, .noProviderConfigured: "key.slash"
        case .notFound, .noProductData: "magnifyingglass"
        case .providerRejected: "exclamationmark.triangle"
        case .providerUnavailable: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        }
    }

    /// Whether retrying the same request could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .timedOut, .rateLimited, .providerUnavailable, .offline: true
        case .invalidURL, .unsupportedURL, .notAuthorized, .notFound,
             .noProductData, .noProviderConfigured, .cancelled, .providerRejected: false
        }
    }

    /// Whether the sensible next step is to open Settings.
    var suggestsSettings: Bool {
        switch self {
        case .notAuthorized, .noProviderConfigured, .providerRejected: true
        default: false
        }
    }

    /// Whether the user can still save something useful despite the failure.
    var allowsManualEntry: Bool {
        self != .cancelled
    }
}
