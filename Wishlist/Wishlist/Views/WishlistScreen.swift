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

    @State private var path: [WishlistItem.ID] = []
    @State private var searchText = ""
    @State private var isAddingItem = false
    @State private var editingItem: WishlistItem?
    @State private var pendingDeletion: WishlistItem?
    @State private var addExit: AddItemExit = .none

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
                                    Task { await repository.refreshPrices() }
                                } label: {
                                    Label(String(localized: "Refresh Prices"), systemImage: "arrow.clockwise")
                                }
                                .disabled(repository.isRefreshing || repository.activeItems.isEmpty)
                            }
                        } label: {
                            Label(String(localized: "More"), systemImage: "ellipsis.circle")
                        }

                        Button {
                            isAddingItem = true
                        } label: {
                            Label(String(localized: "Add Item"), systemImage: "plus")
                        }
                    }
                }
                .refreshable {
                    await repository.refreshPrices()
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
        List {
            Section {
                ForEach(visibleItems) { item in
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
                            onDelete: { requestDeletion(of: item) }
                        )
                    }
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
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
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

    private var visibleItems: [WishlistItem] {
        repository.activeItems(sortedBy: settings.sortOrder, matching: searchText)
    }

    /// "6 items · £412.98" — a total only when every item shares a currency,
    /// because adding pounds to dollars would be a fiction.
    private var listSummary: String? {
        let count = repository.activeItems.count
        guard count > 0 else { return nil }
        let itemsText = count == 1
            ? String(localized: "1 item")
            : String(localized: "\(count) items")
        guard let total = repository.activeTotal else { return itemsText }
        return itemsText + " · " + total.formatted
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
