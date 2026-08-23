//
//  WishlistScreen.swift
//  Wishlist
//
//  The main screen. A plain list, because the job here is scanning and
//  comparing: picture to recognise, name to identify, price to judge.
//

import SwiftUI
import Foundation

struct WishlistScreen: View {
    @Environment(WishlistRepository.self) private var repository
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppRouter.self) private var router
    @Environment(PriceAlertCenter.self) private var alerts

    @State private var path: [WishlistItem.ID] = []
    @State private var searchText = ""
    @State private var isAddingItem = false
    @State private var editingItem: WishlistItem?
    @State private var pendingDeletion: WishlistItem?
    @State private var addExit: AddItemExit = .none
    @State private var askingAbout: WishlistItem?
    @State private var isAskingGenerally = false
    @State private var selectedWishlistID: UUID?
    @State private var isNamingWishlist = false
    @State private var newWishlistName = ""
    @State private var isManagingWishlists = false
    @State private var onlyWithinBudget = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack(path: $path) {
            content
                .navigationTitle(Text(activeWishlistName))
                .navigationDestination(for: WishlistItem.ID.self) { id in
                    ItemDetailScreen(itemID: id)
                }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search Wishlist")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker(selection: $selectedWishlistID) {
                                Label(String(localized: "All Items"), systemImage: "tray.full")
                                    .tag(UUID?.none)
                                ForEach(repository.sortedWishlists) { list in
                                    Label(list.displayName, systemImage: list.symbolName)
                                        .tag(UUID?.some(list.id))
                                }
                            } label: {
                                Text("Wishlist")
                            }
                            .pickerStyle(.inline)

                            Section {
                                if settings.availableToSpend != nil {
                                    Toggle(isOn: $onlyWithinBudget) {
                                        Label(String(localized: "Within Budget"), systemImage: "creditcard")
                                    }
                                }
                                Button {
                                    newWishlistName = ""
                                    isNamingWishlist = true
                                } label: {
                                    Label(String(localized: "New Wishlist"), systemImage: "plus")
                                }
                                Button {
                                    isManagingWishlists = true
                                } label: {
                                    Label(String(localized: "Edit Wishlists"), systemImage: "slider.horizontal.3")
                                }
                            }
                        } label: {
                            Label(
                                String(localized: "Wishlists"),
                                systemImage: isNarrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                            )
                        }
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Picker(selection: $settings.sortOrder) {
                                ForEach(WishlistSortOrder.allCases) { order in
                                    Label(order.label, systemImage: order.symbolName).tag(order)
                                }
                            } label: {
                                Text("Sort By")
                            }
                            .pickerStyle(.inline)

                            Section {
                                Button {
                                    Task { await refreshPrices() }
                                } label: {
                                    Label(String(localized: "Refresh Prices"), systemImage: "arrow.clockwise")
                                }
                                .disabled(repository.isRefreshing || repository.activeItems.isEmpty)
                            }
                        } label: {
                            Label(String(localized: "More"), systemImage: "ellipsis.circle")
                        }

                        Button {
                            isAskingGenerally = true
                        } label: {
                            Label(String(localized: "Ask the Assistant"), systemImage: "sparkles")
                        }

                        Button {
                            isAddingItem = true
                        } label: {
                            Label(String(localized: "Add Item"), systemImage: "plus")
                        }
                    }
                }
                .refreshable {
                    await refreshPrices()
                }
                .sheet(isPresented: $isAddingItem) {
                    AddItemSheet(exit: $addExit, wishlistID: selectedWishlistID)
                }
                .onChange(of: isAddingItem) { _, isPresented in
                    // Wait for the sheet to finish dismissing before pushing or
                    // switching tabs; doing both at once loses the transition.
                    guard !isPresented else { return }
                    switch addExit {
                    case .none:
                        break
                    case .openItem(let id):
                        path = [id]
                    case .openSettings:
                        router.showSettings()
                    }
                    addExit = .none
                }
                .sheet(item: $editingItem) { item in
                    ItemEditorSheet(mode: .edit(item))
                }
                .sheet(item: $askingAbout) { item in
                    AskAssistantSheet(item: item)
                }
                .sheet(isPresented: $isAskingGenerally) {
                    AskAssistantSheet(item: nil)
                }
                .sheet(isPresented: $isManagingWishlists) {
                    WishlistsManagerView()
                }
                .onChange(of: repository.wishlists) { _, lists in
                    // A list can be deleted from the manager while it is the
                    // one being shown. Fall back to All Items rather than
                    // filtering by something that no longer exists.
                    guard let selected = selectedWishlistID else { return }
                    if !lists.contains(where: { $0.id == selected }) {
                        selectedWishlistID = nil
                    }
                }
                .alert(String(localized: "New Wishlist"), isPresented: $isNamingWishlist) {
                    TextField(String(localized: "Name"), text: $newWishlistName)
                        .textInputAutocapitalization(.words)
                    Button(String(localized: "Create")) {
                        // Switching to it immediately is what someone naming a
                        // list is about to want.
                        if let created = repository.addWishlist(name: newWishlistName) {
                            selectedWishlistID = created.id
                        }
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: {
                    Text("Group things you want — Tech, Back to School, Kitchen.")
                }
                .overlay(alignment: .bottom) {
                    FeedbackOverlay()
                }
                .sensoryFeedback(trigger: repository.lastAction?.id) { _, _ in
                    guard settings.hapticsEnabled else { return nil }
                    switch repository.lastAction?.kind {
                    case .some(.obtained): return .success
                    case .some(.restored): return .selection
                    case .some(.deleted): return .impact(flexibility: .soft)
                    case .none: return nil
                    }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if repository.isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading your wishlist"))
        } else if repository.loadFailed {
            ContentUnavailableView {
                Label(String(localized: "Couldn’t Open Your Wishlist"), systemImage: "exclamationmark.triangle")
            } description: {
                Text("Your saved items couldn’t be read. A copy has been kept in case it can be recovered.")
            } actions: {
                Button(String(localized: "Try Again")) {
                    Task { await repository.load() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if !pinnedItems.isEmpty {
                Section {
                    ForEach(pinnedItems) { item in
                        row(for: item)
                    }
                } header: {
                    sectionHeader(String(localized: "Pinned"), symbol: "pin.fill")
                } footer: {
                    // Only when nothing follows, so the total is always last.
                    if unpinnedItems.isEmpty { summaryFooter }
                }
            }

            if !unpinnedItems.isEmpty {
                Section {
                    ForEach(unpinnedItems) { item in
                        row(for: item)
                    }
                } header: {
                    // Headers are sticky in a plain list. Without one here,
                    // "Pinned" stayed stuck to the top of the screen for the
                    // whole scroll — still claiming to label rows that were
                    // nothing of the kind. This both separates the groups and
                    // takes over the sticky slot at the boundary, so whatever
                    // is at the top of the screen always names what you are
                    // looking at.
                    if !pinnedItems.isEmpty {
                        sectionHeader(String(localized: "Everything Else"))
                    }
                } footer: {
                    summaryFooter
                }
            }
        }
        .listStyle(.plain)
    }

    private func sectionHeader(_ title: String, symbol: String? = nil) -> some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .textCase(nil)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// A count and a total summarise what you have just read, so they belong
    /// after it — the way a statement totals at the bottom, and the way the
    /// Obtained screen already does it. Between Pinned and the rest it read as
    /// a heading for the wrong thing.
    @ViewBuilder
    private var summaryFooter: some View {
        if searchText.isEmpty, let summary = listSummary {
            Text(summary)
                .textCase(nil)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .accessibilityLabel(Text(summary))
        }
    }

    /// Shared by the pinned and unpinned sections, so the two can never drift
    /// apart in what a row offers.
    private func row(for item: WishlistItem) -> some View {
        NavigationLink(value: item.id) {
            ItemRow(item: item)
        }
        // Presented from the row rather than from the screen, so the question
        // is anchored to the thing it is about instead of to the whole list.
        .confirmationDialog(
            Text(deletionTitle(for: item)),
            isPresented: deletionBinding(for: item),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                repository.delete(id: item.id)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This item will be removed from your wishlist.")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                repository.markObtained(id: item.id)
            } label: {
                Label(String(localized: "Obtained"), systemImage: "checkmark.circle.fill")
            }
            .tint(.green)

            Button {
                repository.setPinned(!item.isPinned, for: item.id)
            } label: {
                Label(
                    item.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                    systemImage: item.isPinned ? "pin.slash.fill" : "pin.fill"
                )
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDeletion(of: item)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }

            Button {
                editingItem = item
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .contextMenu {
            ItemActionsMenu(
                item: item,
                onEdit: { editingItem = item },
                onDelete: { requestDeletion(of: item) },
                onAsk: { askingAbout = item }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if let list = repository.wishlist(id: selectedWishlistID), !onlyWithinBudget {
            // A list you just made is empty by definition. The useful thing to
            // offer is adding to it, not undoing the "filter" you deliberately
            // applied by opening it.
            ContentUnavailableView {
                Label(list.displayName, systemImage: list.symbolName)
            } description: {
                Text("Nothing on this list yet. Anything you add while you're here joins it.")
            } actions: {
                Button {
                    isAddingItem = true
                } label: {
                    Label(String(localized: "Add Item"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if isNarrowed {
            // A filter hiding everything must not read as an empty wishlist.
            ContentUnavailableView {
                Label(String(localized: "Nothing Matches"), systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(narrowedEmptyDescription)
            } actions: {
                Button(String(localized: "Show All Items")) {
                    selectedWishlistID = nil
                    onlyWithinBudget = false
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "Nothing on Your Wishlist"), systemImage: "star")
            } description: {
                Text("Paste a link to something you want and Wishlist will fill in the details.")
            } actions: {
                Button {
                    isAddingItem = true
                } label: {
                    Label(String(localized: "Add Item"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Derived

    private var currentFilter: WishlistFilter {
        WishlistFilter(
            searchText: searchText,
            wishlistID: selectedWishlistID,
            withinBudget: onlyWithinBudget
        )
    }

    /// The screen is named after the list you are looking at.
    private var activeWishlistName: String {
        repository.wishlist(id: selectedWishlistID)?.displayName
            ?? String(localized: "Wishlist")
    }

    private var isNarrowed: Bool { currentFilter.isNarrowed }



    private var visibleItems: [WishlistItem] {
        repository.activeItems(
            sortedBy: settings.sortOrder,
            filter: currentFilter,
            budget: settings.availableToSpend
        )
    }

    private var narrowedEmptyDescription: String {
        let name = repository.wishlist(id: selectedWishlistID)?.displayName
        if let name, onlyWithinBudget {
            return String(localized: "Nothing in “\(name)” fits your budget.")
        }
        if let name {
            return String(localized: "There’s nothing in “\(name)” yet. Add something and it will appear here.")
        }
        return String(localized: "Nothing on your wishlist fits your budget right now.")
    }

    private var pinnedItems: [WishlistItem] { visibleItems.filter(\.isPinned) }

    private var unpinnedItems: [WishlistItem] { visibleItems.filter { !$0.isPinned } }

    private func refreshPrices() async {
        await repository.refreshPrices()
        guard settings.notifiesPriceDrops else { return }
        await alerts.announce(repository.lastPriceDrops)
    }

    /// "Kitchen · 6 items · £412.98 · £150.00 to spend" — each part only when
    /// it is true. A total appears only when every item shares a currency,
    /// because adding pounds to dollars would be a fiction.
    private var listSummary: String? {
        let shown = visibleItems
        guard !shown.isEmpty else { return nil }

        var parts: [String] = []

        parts.append(shown.count == 1
            ? String(localized: "1 item")
            : String(localized: "\(shown.count) items"))
        if let total = Money.total(of: shown.compactMap(\.price)) {
            parts.append(total.formatted)
        }
        if let budget = settings.availableToSpend {
            parts.append(String(localized: "\(budget.formatted) to spend"))
        }
        return parts.joined(separator: " · ")
    }

    private func deletionTitle(for item: WishlistItem) -> String {
        String(localized: "Delete “\(item.displayName)”?")
    }

    /// One dialog per row, each true only for the row being deleted, so the
    /// list never presents more than one.
    private func deletionBinding(for item: WishlistItem) -> Binding<Bool> {
        Binding(
            get: { pendingDeletion?.id == item.id },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func requestDeletion(of item: WishlistItem) {
        if settings.confirmBeforeDeleting {
            pendingDeletion = item
        } else {
            repository.delete(id: item.id)
        }
    }
}

/// The bottom slot: undo after a change, or a one-line result after a refresh.
/// Never both, never for long.
struct FeedbackOverlay: View {
    @Environment(WishlistRepository.self) private var repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let action = repository.lastAction {
                UndoBanner(action: action) {
                    repository.undoLastAction()
                }
                .transition(transition)
            } else if let summary = repository.refreshSummary {
                Text(summary)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(transition)
            }
        }
        .padding(.bottom, 8)
        .animation(animation, value: repository.lastAction?.id)
        .animation(animation, value: repository.refreshSummary)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }
}

#Preview {
    WishlistScreen().withPreviewEnvironment()
}
