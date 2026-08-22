//
//  ProductLookupService.swift
//  Wishlist
//
//  The pipeline, in one place:
//
//      input → validate → resolve redirects → provider chain → merge → snapshot
//
//  Providers are consulted in order and their results are merged field by
//  field, so a price from Amazon and an image from the product page combine
//  into one item. The chain stops as soon as the snapshot is complete, which
//  keeps the common case to a single request.
//

import Foundation
import OSLog

/// Where the pipeline currently is, so the Add screen can say something true
/// while the user waits.
nonisolated enum LookupStage: Sendable, Equatable {
    case validating
    case resolvingLink
    case contacting(String)
    case tidying
    case finishing

    var message: String {
        switch self {
        case .validating: String(localized: "Checking the link…")
        case .resolvingLink: String(localized: "Following the link…")
        case .contacting(let message): message
        case .tidying: String(localized: "Tidying up…")
        case .finishing: String(localized: "Almost there…")
        }
    }
}

nonisolated struct LookupOutcome: Sendable {
    var snapshot: ProductSnapshot
    var link: ProductLink?
    /// The name to use if the providers could not find one.
    var fallbackName: String
    /// Set when some providers failed but others succeeded, so the UI can
    /// explain why a field is missing without treating the lookup as failed.
    var partialFailure: LookupError?

    var item: WishlistItem {
        snapshot.makeItem(fallbackName: fallbackName, requestedURL: link?.canonicalURL)
    }
}

nonisolated final class ProductLookupService: Sendable {
    private let http: HTTPClient
    private let providers: [any ProductDataProvider]
    private let models: LanguageModelRouter
    private let polisher = SnapshotPolisher()
    private let coalescer = TaskCoalescer<ProductSnapshot>()
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "lookup")

    init(
        http: HTTPClient,
        providers: [any ProductDataProvider],
        models: LanguageModelRouter
    ) {
        self.http = http
        self.providers = providers
        self.models = models
    }

    /// The chain used by the app, and every step of it is free to use: Amazon's
    /// own API first for Amazon links, then the store's product page, then a
    /// rendering service for pages that refuse to be read directly.
    static func makeDefault(http: HTTPClient = URLSessionHTTPClient()) -> ProductLookupService {
        let models = LanguageModelRouter(http: http)
        return ProductLookupService(
            http: http,
            providers: [
                AmazonPAAPIProvider(http: http),
                WebPageProvider(http: http, models: models),
                MicrolinkProvider(http: http)
            ],
            models: models
        )
    }

    // MARK: - Interactive lookup

    /// Looks up whatever the user typed: a link, a product name, or a link with
    /// a name they would rather use.
    func lookup(
        urlText: String?,
        nameText: String?,
        credentials: LookupCredentials,
        isOnline: Bool = true,
        onStage: @Sendable @escaping (LookupStage) -> Void = { _ in }
    ) async throws -> LookupOutcome {
        let trimmedURL = urlText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedName = nameText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedURL.isEmpty || !trimmedName.isEmpty else {
            throw LookupError.invalidURL
        }

        // Without a link there is nothing to validate; a name-only entry is a
        // perfectly good wishlist item even when no provider can search.
        guard !trimmedURL.isEmpty else {
            let request = LookupRequest(link: nil, searchTerm: trimmedName)
            guard isOnline else {
                return LookupOutcome(
                    snapshot: ProductSnapshot(),
                    link: nil,
                    fallbackName: trimmedName,
                    partialFailure: .offline
                )
            }
            let (snapshot, failure) = await runChain(request, credentials: credentials, onStage: onStage)
            return LookupOutcome(
                snapshot: await polished(snapshot, credentials: credentials, onStage: onStage),
                link: nil,
                fallbackName: trimmedName,
                partialFailure: snapshot.isEmpty ? failure : nil
            )
        }

        onStage(.validating)
        var link = try URLValidator.validate(trimmedURL)

        guard isOnline else { throw LookupError.offline }

        var prefetched: PrefetchedPage?
        if link.isShortened {
            onStage(.resolvingLink)
            (link, prefetched) = try await resolve(link)
        }

        let request = LookupRequest(
            link: link,
            searchTerm: trimmedName.isEmpty ? nil : trimmedName,
            prefetchedPage: prefetched
        )
        let (snapshot, failure) = await runChain(request, credentials: credentials, onStage: onStage)

        if snapshot.isEmpty, let failure {
            throw failure
        }

        onStage(.finishing)
        return LookupOutcome(
            snapshot: await polished(snapshot, credentials: credentials, onStage: onStage),
            link: link,
            fallbackName: trimmedName.isEmpty ? (link.retailer.name) : trimmedName,
            partialFailure: snapshot.isPartial ? failure : nil
        )
    }

    /// Shortens a keyword-stuffed title and fills in a missing category, when
    /// the user has asked for that. Never runs on a refresh: an item that is
    /// already on the list keeps the name it was saved under.
    private func polished(
        _ snapshot: ProductSnapshot,
        credentials: LookupCredentials,
        onStage: @Sendable @escaping (LookupStage) -> Void
    ) async -> ProductSnapshot {
        guard let client = models.client(for: credentials.intelligence) else { return snapshot }
        onStage(.tidying)
        return await polisher.polished(
            snapshot,
            settings: credentials.intelligence,
            client: client
        )
    }

    // MARK: - Background refresh

    /// Re-reads an item's current price and availability. Identical concurrent
    /// refreshes share one request.
    func refresh(
        productURL: URL,
        credentials: LookupCredentials
    ) async throws -> ProductSnapshot {
        let link = try URLValidator.validate(productURL.absoluteString)
        let request = LookupRequest(link: link, searchTerm: nil, purpose: .priceCheck)
        let providers = self.providers

        return try await coalescer.run(key: request.coalescingKey, priority: .utility) { [self] in
            let (snapshot, failure) = await Self.runChain(
                request,
                credentials: credentials,
                providers: providers,
                log: log,
                onStage: { _ in }
            )
            if snapshot.isEmpty { throw failure ?? LookupError.noProductData }
            return snapshot
        }
    }

    // MARK: - Chain

    private func runChain(
        _ request: LookupRequest,
        credentials: LookupCredentials,
        onStage: @Sendable @escaping (LookupStage) -> Void
    ) async -> (ProductSnapshot, LookupError?) {
        await Self.runChain(
            request,
            credentials: credentials,
            providers: providers,
            log: log,
            onStage: onStage
        )
    }

    private static func runChain(
        _ request: LookupRequest,
        credentials: LookupCredentials,
        providers: [any ProductDataProvider],
        log: Logger,
        onStage: @Sendable @escaping (LookupStage) -> Void
    ) async -> (ProductSnapshot, LookupError?) {
        var merged = ProductSnapshot()
        var failures: [LookupError] = []
        var attempted = false
        let deadline = Date.now.addingTimeInterval(request.purpose.budget)

        for provider in providers {
            if Task.isCancelled { return (merged, .cancelled) }
            // Return what we have rather than let a slow chain keep the user
            // waiting past the point the answer is useful.
            if Date.now >= deadline { break }
            // A provider that can never return a price has nothing to add to a
            // price check, so it is not called at all.
            if request.purpose == .priceCheck, !provider.canProvidePrice { continue }
            guard provider.canHandle(request, credentials: credentials) else { continue }
            // Nothing left to ask for.
            if isComplete(merged, for: request.purpose) { break }

            attempted = true
            onStage(.contacting(provider.progressMessage))
            do {
                let snapshot = try await provider.fetch(request, credentials: credentials)
                merged = merged.merging(snapshot)
            } catch let error as LookupError {
                if error == .cancelled { return (merged, .cancelled) }
                log.notice("Provider \(provider.identifier, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                failures.append(error)
            } catch {
                log.error("Provider \(provider.identifier, privacy: .public) threw an unexpected error")
                failures.append(.providerUnavailable(provider: provider.displayName))
            }
        }

        if !attempted {
            return (merged, request.link == nil ? .noProviderConfigured : .unsupportedURL(host: request.link?.host))
        }
        return (merged, mostInformative(failures))
    }

    /// Whether asking another provider could still improve the result.
    ///
    /// Availability deliberately does not count towards a full lookup: plenty
    /// of legitimate product pages never state it, and requiring it meant the
    /// chain ran every remaining provider on almost every successful lookup.
    private static func isComplete(_ snapshot: ProductSnapshot, for purpose: LookupPurpose) -> Bool {
        switch purpose {
        case .full:
            return snapshot.name != nil && snapshot.price != nil && snapshot.imageURL != nil
        case .priceCheck:
            return snapshot.price != nil
        }
    }

    /// Picks the failure that best explains what the user should do, rather
    /// than whichever happened to come last.
    private static func mostInformative(_ failures: [LookupError]) -> LookupError? {
        guard !failures.isEmpty else { return nil }
        let ranking: [(LookupError) -> Bool] = [
            { if case .notAuthorized = $0 { return true }; return false },
            { if case .rateLimited = $0 { return true }; return false },
            { $0 == .offline },
            { $0 == .timedOut },
            { $0 == .notFound },
            { if case .unsupportedURL = $0 { return true }; return false },
            { $0 == .noProductData }
        ]
        for matches in ranking {
            if let failure = failures.first(where: matches) { return failure }
        }
        return failures.first
    }

    // MARK: - Redirects

    /// Follows a shortened link to the real product page. URLSession has
    /// already followed the redirects, so the response tells us where we landed
    /// — and the page it returned is kept so it need not be fetched twice.
    private func resolve(_ link: ProductLink) async throws -> (ProductLink, PrefetchedPage?) {
        let response = try await http.send(
            WebPageProvider.makeRequest(for: link.canonicalURL),
            provider: String(localized: "Product page")
        )
        guard let finalURL = response.url, finalURL != link.canonicalURL else {
            return (link, PrefetchedPage(response: response))
        }
        let resolved = try URLValidator.validate(finalURL.absoluteString)
        return (resolved, PrefetchedPage(response: response))
    }
}

/// A page body that has already been downloaded, handed to the provider chain
/// so a redirect resolution does not cost an extra request.
nonisolated struct PrefetchedPage: Sendable, Hashable {
    var data: Data
    var contentType: String?
    var url: URL?

    init(data: Data, contentType: String?, url: URL?) {
        self.data = data
        self.contentType = contentType
        self.url = url
    }

    init(response: HTTPResponse) {
        self.init(
            data: response.data,
            contentType: response.headerValue("Content-Type"),
            url: response.url
        )
    }
}
