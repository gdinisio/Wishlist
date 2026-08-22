//
//  WishlistRepository.swift
//  Wishlist
//
//  The app's single source of truth. Views read from it and call methods on it;
//  they never touch the store or the network directly. Everything here runs on
//  the main actor and hands the slow work — disk, network — to the layers
//  below, so the UI is never blocked.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class WishlistRepository {
    // MARK: - State

    private(set) var items: [WishlistItem] = []
    private(set) var isLoading = true
    /// Set when the saved wishlist could not be read, so the UI can say so
    /// rather than silently showing an empty list.
    private(set) var loadFailed = false
    private(set) var isRefreshing = false
    /// The most recent reversible change, driving the undo affordance.
    private(set) var lastAction: UndoableAction?
    /// Result of the last price refresh, shown briefly and then cleared.
    private(set) var refreshSummary: String?
    /// Price falls seen in the last refresh, for whoever wants to announce them.
    private(set) var lastPriceDrops: [PriceDrop] = []

    // MARK: - Dependencies

    private let store: any WishlistPersisting
    private let lookup: ProductLookupService
    private let credentialsProvider: @MainActor () -> LookupCredentials
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "repository")

    private var saveTask: Task<Void, Never>?
    private var undoExpiryTask: Task<Void, Never>?

    init(
        store: any WishlistPersisting,
        lookup: ProductLookupService,
        credentialsProvider: @escaping @MainActor () -> LookupCredentials
    ) {
        self.store = store
        self.lookup = lookup
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        loadFailed = false
        do {
            items = try await store.load()
        } catch {
            loadFailed = true
            items = []
            log.error("Failed to load wishlist: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Reading

    var activeItems: [WishlistItem] {
        items.filter { $0.status == .active }
    }

    var obtainedItems: [WishlistItem] {
        items.filter { $0.status == .obtained }
            .sorted { ($0.dateObtained ?? $0.dateAdded) > ($1.dateObtained ?? $1.dateAdded) }
    }

    func item(id: WishlistItem.ID) -> WishlistItem? {
        items.first { $0.id == id }
    }

    /// Active items, sorted and filtered for the wishlist screen.
    func activeItems(
        sortedBy order: WishlistSortOrder,
        filter: WishlistFilter = WishlistFilter(),
        budget: Money? = nil
    ) -> [WishlistItem] {
        var result = Self.filter(activeItems, query: filter.searchText)
        if let collection = filter.collection {
            result = result.filter { $0.collectionName == collection }
        }
        if filter.withinBudget, let budget {
            result = result.filter { $0.fits(within: budget) }
        }
        return Self.sort(result, by: order)
    }

    /// Every collection in use, alphabetically. Derived rather than stored, so
    /// a collection stops existing the moment nothing is in it.
    var collectionNames: [String] {
        var seen = Set<String>()
        for item in items {
            if let name = item.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                seen.insert(name)
            }
        }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func setCollection(_ name: String?, for id: WishlistItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].collectionName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        items[index].touch()
        scheduleSave()
    }

    func obtainedItems(matching query: String) -> [WishlistItem] {
        Self.filter(obtainedItems, query: query)
    }

    /// Total value of the active list, when every item shares a currency.
    var activeTotal: Money? {
        Money.total(of: activeItems.compactMap(\.price))
    }

    static func filter(_ items: [WishlistItem], query: String) -> [WishlistItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            [item.name, item.brand, item.category, item.displayRetailer, item.notes]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    static func sort(_ items: [WishlistItem], by order: WishlistSortOrder) -> [WishlistItem] {
        switch order {
        case .dateAddedDescending:
            return items.sorted { $0.dateAdded > $1.dateAdded }
        case .dateAddedAscending:
            return items.sorted { $0.dateAdded < $1.dateAdded }
        case .name:
            return items.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .priceAscending:
            // Items without a price sort last: an unknown price is not a low one.
            return items.sorted { lhs, rhs in
                switch (lhs.price?.amount, rhs.price?.amount) {
                case let (left?, right?): return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.dateAdded > rhs.dateAdded
                }
            }
        case .priceDescending:
            return items.sorted { lhs, rhs in
                switch (lhs.price?.amount, rhs.price?.amount) {
                case let (left?, right?): return left > right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.dateAdded > rhs.dateAdded
                }
            }
        }
    }

    // MARK: - Duplicates

    /// Finds an item already saved for this product. Matches on the canonical
    /// URL first, then on an Amazon ASIN, then on an identical name at the same
    /// retailer — the three ways the same product actually shows up twice.
    func existingItem(forURL url: URL?, name: String?, retailer: Retailer?) -> WishlistItem? {
        if let url, let link = try? URLValidator.validate(url.absoluteString) {
            if let match = items.first(where: { candidate in
                guard let candidateURL = candidate.productURL,
                      let candidateLink = try? URLValidator.validate(candidateURL.absoluteString)
                else { return false }
                if let asin = link.amazonASIN, let candidateASIN = candidateLink.amazonASIN {
                    return asin == candidateASIN
                }
                return candidateLink.canonicalURL == link.canonicalURL
            }) {
                return match
            }
        }
        guard let name, !name.isEmpty else { return nil }
        return items.first { candidate in
            candidate.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                && candidate.displayRetailer?.lowercased() == retailer?.name.lowercased()
        }
    }

    // MARK: - Writing

    func add(_ item: WishlistItem) {
        items.append(item)
        scheduleSave()
    }

    func update(_ item: WishlistItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.touch()
        items[index] = updated
        scheduleSave()
    }

    func delete(id: WishlistItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        register(UndoableAction(kind: .deleted, item: removed, index: index))
        scheduleSave()
    }

    func delete(ids: [WishlistItem.ID]) {
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first {
            delete(id: id)
            return
        }
        items.removeAll { ids.contains($0.id) }
        clearUndo()
        scheduleSave()
    }

    func markObtained(id: WishlistItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items[index]
        items[index].markObtained()
        register(UndoableAction(kind: .obtained, item: previous, index: index))
        scheduleSave()
    }

    func returnToWishlist(id: WishlistItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items[index]
        items[index].returnToWishlist()
        register(UndoableAction(kind: .restored, item: previous, index: index))
        scheduleSave()
    }

    func setNotes(_ notes: String?, for id: WishlistItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].notes = (trimmed?.isEmpty ?? true) ? nil : trimmed
        items[index].touch()
        scheduleSave()
    }

    func deleteAll() {
        items.removeAll()
        clearUndo()
        scheduleSave()
    }

    // MARK: - Undo

    private func register(_ action: UndoableAction) {
        lastAction = action
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            // Long enough to notice and act on, short enough to stay out of the
            // way — matching the feel of system undo affordances.
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.clearUndo()
        }
    }

    func clearUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        lastAction = nil
    }

    func undoLastAction() {
        guard let action = lastAction else { return }
        switch action.kind {
        case .obtained, .restored:
            if let index = items.firstIndex(where: { $0.id == action.item.id }) {
                items[index] = action.item
            } else {
                items.append(action.item)
            }
        case .deleted:
            let index = min(action.index, items.count)
            items.insert(action.item, at: index)
        }
        clearUndo()
        scheduleSave()
    }

    // MARK: - Refreshing

    /// Re-reads prices for everything on the active list. Runs a small number
    /// of lookups at a time so a long wishlist does not open thirty sockets.
    func refreshPrices() async {
        guard !isRefreshing else { return }
        let credentials = credentialsProvider()
        let targets = activeItems.filter { $0.productURL != nil }
        guard !targets.isEmpty else {
            refreshSummary = String(localized: "Nothing to refresh")
            scheduleSummaryClear()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        var updatedCount = 0
        var failureCount = 0
        var drops: [PriceDrop] = []
        let batchSize = 3

        for batch in stride(from: 0, to: targets.count, by: batchSize) {
            let slice = Array(targets[batch..<min(batch + batchSize, targets.count)])
            let results = await withTaskGroup(
                of: (WishlistItem.ID, ProductSnapshot?).self,
                returning: [(WishlistItem.ID, ProductSnapshot?)].self
            ) { group in
                for item in slice {
                    guard let url = item.productURL else { continue }
                    group.addTask { [lookup] in
                        let snapshot = try? await lookup.refresh(productURL: url, credentials: credentials)
                        return (item.id, snapshot)
                    }
                }
                var collected: [(WishlistItem.ID, ProductSnapshot?)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            for (id, snapshot) in results {
                guard let snapshot else { failureCount += 1; continue }
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                let hadPrice = items[index].price
                apply(snapshot, to: &items[index])
                if items[index].price != hadPrice {
                    updatedCount += 1
                    if let was = hadPrice, let now = items[index].price,
                       was.canCompare(with: now), now.amount < was.amount {
                        drops.append(PriceDrop(item: items[index], previous: was))
                    }
                }
            }
            if Task.isCancelled { break }
        }

        scheduleSave()
        lastPriceDrops = drops
        refreshSummary = Self.refreshMessage(updated: updatedCount, failed: failureCount)
        scheduleSummaryClear()
    }

    /// Updates one item from its store, used from its detail view.
    ///
    /// An item still missing headline details gets a full lookup; one that only
    /// wants a current price does not pay for the rest of the chain. That is
    /// why there is a single "Update from Store" action rather than two the
    /// user has to choose between.
    @discardableResult
    func refresh(id: WishlistItem.ID) async -> LookupError? {
        guard let item = item(id: id), let url = item.productURL else {
            return .unsupportedURL(host: nil)
        }
        let purpose: LookupPurpose = item.missingFields.isEmpty ? .priceCheck : .full
        do {
            let snapshot = try await lookup.refresh(
                productURL: url,
                credentials: credentialsProvider(),
                purpose: purpose
            )
            guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
            apply(snapshot, to: &items[index])
            scheduleSave()
            return nil
        } catch let error as LookupError {
            return error
        } catch {
            return .providerUnavailable(provider: nil)
        }
    }

    /// Only ever fills in or updates what the provider actually returned. A
    /// field the provider omitted keeps the value the user already has.
    private func apply(_ snapshot: ProductSnapshot, to item: inout WishlistItem) {
        item.recordPrice(snapshot.price)
        if snapshot.availability != .unknown { item.availability = snapshot.availability }
        if item.imageURL == nil { item.imageURL = snapshot.imageURL }
        if item.brand == nil { item.brand = snapshot.brand }
        if item.category == nil { item.category = snapshot.category }
        if item.details == nil { item.details = snapshot.details }
        if item.retailer == nil { item.retailer = snapshot.retailer }
        for source in snapshot.sources where !item.sources.contains(source) {
            item.sources.append(source)
        }
        item.dateRefreshed = .now
        item.touch()
    }

    private static func refreshMessage(updated: Int, failed: Int) -> String {
        if updated == 0 && failed == 0 { return String(localized: "Prices are up to date") }
        if updated == 0 { return String(localized: "Couldn’t check prices right now") }
        if updated == 1 { return String(localized: "1 price updated") }
        return String(localized: "\(updated) prices updated")
    }

    private func scheduleSummaryClear() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.refreshSummary = nil
        }
    }

    // MARK: - Saving

    /// Writes are coalesced: a burst of edits produces one disk write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.write(snapshot)
        }
    }

    /// Called when the app leaves the foreground, so nothing waits on a timer.
    func saveNow() async {
        saveTask?.cancel()
        await write(items)
    }

    private func write(_ snapshot: [WishlistItem]) async {
        do {
            try await store.save(snapshot)
        } catch {
            log.error("Failed to save wishlist: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Supporting types

nonisolated struct UndoableAction: Identifiable, Sendable {
    enum Kind: Sendable {
        case obtained
        case restored
        case deleted
    }

    let id = UUID()
    var kind: Kind
    /// The item exactly as it was before the change.
    var item: WishlistItem
    var index: Int

    var message: String {
        switch kind {
        case .obtained: String(localized: "Marked as obtained")
        case .restored: String(localized: "Moved back to Wishlist")
        case .deleted: String(localized: "Item deleted")
        }
    }

    var symbolName: String {
        switch kind {
        case .obtained: "checkmark.circle.fill"
        case .restored: "arrow.uturn.backward.circle.fill"
        case .deleted: "trash.fill"
        }
    }
}

/// A price that fell between two observations.
nonisolated struct PriceDrop: Identifiable, Sendable {
    var item: WishlistItem
    var previous: Money

    var id: WishlistItem.ID { item.id }

    var saving: Money? {
        guard let now = item.price, now.canCompare(with: previous) else { return nil }
        return Money(amount: previous.amount - now.amount, currencyCode: now.currencyCode)
    }
}

/// What the wishlist screen is currently showing. Held by the view rather than
/// persisted: a filter is a way of looking, not a setting.
nonisolated struct WishlistFilter: Equatable, Sendable {
    var searchText: String = ""
    var collection: String?
    var withinBudget: Bool = false

    /// True when something other than search is narrowing the list, which is
    /// what the toolbar indicator reflects.
    var isNarrowed: Bool { collection != nil || withinBudget }
}

nonisolated enum WishlistSortOrder: String, CaseIterable, Codable, Sendable, Identifiable {
    case dateAddedDescending
    case dateAddedAscending
    case name
    case priceAscending
    case priceDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAddedDescending: String(localized: "Recently Added")
        case .dateAddedAscending: String(localized: "Oldest First")
        case .name: String(localized: "Name")
        case .priceAscending: String(localized: "Price: Low to High")
        case .priceDescending: String(localized: "Price: High to Low")
        }
    }

    var symbolName: String {
        switch self {
        case .dateAddedDescending, .dateAddedAscending: "calendar"
        case .name: "textformat"
        case .priceAscending: "arrow.up.right"
        case .priceDescending: "arrow.down.right"
        }
    }
}
