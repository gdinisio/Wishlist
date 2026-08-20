//
//  ObtainedScreen.swift
//  Wishlist
//
//  History, not a graveyard. Obtained things keep their picture, their price
//  and the date they arrived — and can always go back on the list.
//

import SwiftUI
import Foundation

struct ObtainedScreen: View {
    @Environment(WishlistRepository.self) private var repository
    @Environment(SettingsStore.self) private var settings

    @State private var path: [WishlistItem.ID] = []
    @State private var searchText = ""
    @State private var editingItem: WishlistItem?
    @State private var pendingDeletion: WishlistItem?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("Obtained"))
                .navigationDestination(for: WishlistItem.ID.self) { id in
                    ItemDetailScreen(itemID: id)
                }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search Obtained")
                )
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
                    Text("This permanently removes the item and its history.")
                }
                .overlay(alignment: .bottom) {
                    FeedbackOverlay()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            emptyState
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            NavigationLink(value: item.id) {
                                ItemRow(item: item, showsObtainedDate: true)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    repository.returnToWishlist(id: item.id)
                                } label: {
                                    Label(String(localized: "Wishlist"), systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    requestDeletion(of: item)
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
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
                        Text(DateText.monthTitle(group.month))
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(String(localized: "Nothing Obtained Yet"), systemImage: "checkmark.circle")
            } description: {
                Text("Swipe an item on your wishlist, or open it and mark it as obtained. It will be kept here.")
            }
        }
    }

    // MARK: - Grouping

    private var groups: [ObtainedGroup] {
        let calendar = Calendar.current
        let items = repository.obtainedItems(matching: searchText)
        let grouped = Dictionary(grouping: items) { item -> Date in
            let date = item.dateObtained ?? item.dateAdded
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }
        return grouped
            .map { ObtainedGroup(month: $0.key, items: $0.value) }
            .sorted { $0.month > $1.month }
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

nonisolated struct ObtainedGroup: Identifiable {
    var month: Date
    var items: [WishlistItem]
    var id: Date { month }
}

#Preview {
    ObtainedScreen().withPreviewEnvironment()
}
