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
    @State private var selection = Set<WishlistItem.ID>()
    @State private var editMode: EditMode = .inactive
    @State private var selectedCollection: String?
    @State private var onlyWithinBudget = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("Wishlist"))
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
                        if !visibleItems.isEmpty {
                            EditButton()
                        }
                    }

                    if editMode.isEditing {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button {
                                repository.setPinned(true, forIDs: selection)
                                editMode = .inactive
                            } label: {
                                Label(String(localized: "Pin"), systemImage: "pin")
                            }
                            .disabled(selection.isEmpty)

                            Spacer()

                            Menu {
                                Button(String(localized: "None")) {
                                    repository.setCollection(nil, forIDs: selection)
                                    editMode = .inactive
                                }
                                ForEach(repository.collectionNames, id: \.self) { name in
                                    Button(name) {
                                        repository.setCollection(name, forIDs: selection)
                                        editMode = .inactive
                                    }
                                }
                            } label: {
                                Label(String(localized: "Collection"), systemImage: "folder")
                            }
                            .disabled(selection.isEmpty)

                            Spacer()

                            Button(role: .destructive) {
                                repository.delete(ids: Array(selection))
                                editMode = .inactive
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                            .disabled(selection.isEmpty)
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

                            if !repository.collectionNames.isEmpty {
                                Section {
                                    Picker(selection: $selectedCollection) {
                                        Text("All Collections").tag(String?.none)
                                        ForEach(repository.collectionNames, id: \.self) { name in
                                            Text(name).tag(String?.some(name))
                                        }
                                    } label: {
                                        Text("Collection")
                                    }
                                    .pickerStyle(.inline)
                                }
                            }

                            if settings.availableToSpend != nil {
                                Section {
                                    Toggle(isOn: $onlyWithinBudget) {
                                        Label(String(localized: "Within Budget"), systemImage: "creditcard")
                                    }
                                }
                            }

                            Section {
                                Button {
                                    Task { await refreshPrices() }
                                } label: {
                                    Label(String(localized: "Refresh Prices"), systemImage: "arrow.clockwise")
                                }
                                .disabled(repository.isRefreshing || repository.activeItems.isEmpty)
                            }
                        } label: {
                            // The control keeps its place; only its symbol
                            // changes, so an active filter is visible without
                            // adding a second button to the bar.
                            Label(
                                isNarrowed
                                    ? String(localized: "Filters On")
                                    : String(localized: "More"),
                                systemImage: isNarrowed
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "ellipsis.circle"
                            )
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
                    AddItemSheet(exit: $addExit)
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
                .confirmationDialog(
                    Text(deletionTitle),
                    isPresented: deletionBinding,
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { item in
                    Button(String(localized: "Delete"), role: .destructive) {
                        repository.delete(id: item.id)
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: { _ in
                    Text("This item will be removed from your wishlist.")
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
        List(selection: $selection) {
            if !pinnedItems.isEmpty {
                Section {
                    ForEach(pinnedItems) { item in
                        row(for: item)
                    }
                } header: {
                    Label(String(localized: "Pinned"), systemImage: "pin.fill")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(unpinnedItems) { item in
                    row(for: item)
                }
            } header: {
                if searchText.isEmpty, let summary = listSummary {
                    Text(summary)
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(summary))
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .onChange(of: editMode) { _, mode in
            // A selection that outlives edit mode would act on rows the user
            // can no longer see they picked.
            if !mode.isEditing { selection.removeAll() }
        }
    }

    /// Shared by the pinned and unpinned sections, so the two can never drift
    /// apart in what a row offers.
    private func row(for item: WishlistItem) -> some View {
        NavigationLink(value: item.id) {
            ItemRow(item: item)
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
        } else if isNarrowed {
            // A filter hiding everything must not read as an empty wishlist.
            ContentUnavailableView {
                Label(String(localized: "Nothing Matches"), systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(narrowedEmptyDescription)
            } actions: {
                Button(String(localized: "Show All Items")) {
                    selectedCollection = nil
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
            collection: selectedCollection,
            withinBudget: onlyWithinBudget
        )
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
        if let collection = selectedCollection, onlyWithinBudget {
            return String(localized: "Nothing in “\(collection)” fits your budget.")
        }
        if let collection = selectedCollection {
            return String(localized: "There’s nothing in “\(collection)” yet.")
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
        if let collection = selectedCollection { parts.append(collection) }
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

    private var deletionTitle: String {
        guard let name = pendingDeletion?.displayName else { return String(localized: "Delete Item?") }
        return String(localized: "Delete “\(name)”?")
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
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
