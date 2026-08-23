//
//  WishlistsManagerView.swift
//  Wishlist
//
//  Creating, renaming and removing named lists.
//
//  Deleting a list never deletes what is on it. A list is a way of arranging
//  things you want, and losing a saved product because an arrangement changed
//  would be a bad bargain — so its items simply stop belonging to a list.
//

import SwiftUI
import Foundation

struct WishlistsManagerView: View {
    @Environment(WishlistRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Wishlist?
    @State private var isCreating = false
    @State private var pendingDeletion: Wishlist?

    var body: some View {
        NavigationStack {
            Group {
                if repository.wishlists.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Wishlists Yet"), systemImage: "star")
                    } description: {
                        Text("Group the things you want — Tech, Back to School, Kitchen. Items without a list still show under All Items.")
                    } actions: {
                        Button(String(localized: "New Wishlist")) { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle(Text("Wishlists"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isCreating = true
                    } label: {
                        Label(String(localized: "New Wishlist"), systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { list in
                WishlistEditorSheet(wishlist: list)
            }
            .sheet(isPresented: $isCreating) {
                WishlistEditorSheet(wishlist: nil)
            }
            .confirmationDialog(
                Text(deletionTitle),
                isPresented: deletionBinding,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { list in
                Button(String(localized: "Delete List"), role: .destructive) {
                    repository.deleteWishlist(id: list.id)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { _ in
                Text("The items on it are kept — they just stop belonging to a list.")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(repository.sortedWishlists) { list in
                Button {
                    editing = list
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: list.symbolName)
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        Text(list.displayName)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("\(repository.activeCount(inWishlist: list.id))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // Otherwise the row reads as "Tech, 3" and the 3 is anyone's guess.
                .accessibilityLabel(Text(rowLabel(for: list)))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = list
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rowLabel(for list: Wishlist) -> String {
        let count = repository.activeCount(inWishlist: list.id)
        return count == 1
            ? String(localized: "\(list.displayName), 1 item")
            : String(localized: "\(list.displayName), \(count) items")
    }

    private var deletionTitle: String {
        guard let name = pendingDeletion?.displayName else {
            return String(localized: "Delete List?")
        }
        return String(localized: "Delete “\(name)”?")
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}

/// Naming a list and giving it a symbol. Two decisions, one screen.
struct WishlistEditorSheet: View {
    /// `nil` creates a new list.
    let wishlist: Wishlist?

    @Environment(WishlistRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbolName: String
    @FocusState private var isNameFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 12)]

    init(wishlist: Wishlist?) {
        self.wishlist = wishlist
        _name = State(initialValue: wishlist?.name ?? "")
        _symbolName = State(initialValue: wishlist?.symbolName ?? Wishlist.defaultSymbol)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: symbolName)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)

                        TextField(String(localized: "Name"), text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFocused)
                    }
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Wishlist.symbolChoices, id: \.self) { choice in
                            Button {
                                symbolName = choice
                            } label: {
                                Image(systemName: choice)
                                    .font(.body)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(choice == symbolName ? Color.white : Color.primary)
                                    .background(
                                        choice == symbolName ? Color.accentColor : Color(.secondarySystemFill),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(Self.spokenName(for: choice)))
                            .accessibilityAddTraits(choice == symbolName ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Symbol")
                }
            }
            .navigationTitle(Text(wishlist == nil ? "New Wishlist" : "Edit Wishlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(400))
                if name.isEmpty { isNameFocused = true }
            }
        }
    }

    /// SF Symbol names are dot-separated identifiers, and VoiceOver reads the
    /// dots — "fork dot knife". Say the words instead.
    static func spokenName(for symbolName: String) -> String {
        symbolName
            .split(separator: ".")
            .joined(separator: " ")
    }

    private func save() {
        if var existing = wishlist {
            existing.name = name
            existing.symbolName = symbolName
            repository.updateWishlist(existing)
        } else {
            repository.addWishlist(name: name, symbolName: symbolName)
        }
        dismiss()
    }
}

#Preview {
    WishlistsManagerView().withPreviewEnvironment()
}
