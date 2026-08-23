//
//  ItemActions.swift
//  Wishlist
//
//  One definition of what you can do to an item, reused by the row's context
//  menu and the detail screen's toolbar — so the same gesture in two places
//  offers the same choices in the same order.
//

import SwiftUI
import Foundation
import UIKit

struct ItemActionsMenu: View {
    let item: WishlistItem
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onRefresh: (() -> Void)?
    /// Supplied where a conversation makes sense; omitted elsewhere, so the
    /// menu never offers a dead action.
    var onAsk: (() -> Void)?

    @Environment(WishlistRepository.self) private var repository
    @Environment(\.openURL) private var openURL

    /// Writes straight through to the store, so the menu shows the current
    /// list with a checkmark and changing it is one tap.
    private var wishlistBinding: Binding<UUID?> {
        Binding(
            get: { item.wishlistID },
            set: { repository.setWishlist($0, for: item.id) }
        )
    }

    var body: some View {
        Group {
            if item.isObtained {
                Button {
                    repository.returnToWishlist(id: item.id)
                } label: {
                    Label(String(localized: "Mark as Not Obtained"), systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    repository.markObtained(id: item.id)
                } label: {
                    Label(String(localized: "Mark as Obtained"), systemImage: "checkmark.circle")
                }
            }

            if !item.isObtained {
                Button {
                    repository.setPinned(!item.isPinned, for: item.id)
                } label: {
                    Label(
                        item.isPinned
                            ? String(localized: "Unpin")
                            : String(localized: "Pin to Top"),
                        systemImage: item.isPinned ? "pin.slash" : "pin"
                    )
                }
            }

            if let onAsk {
                Button {
                    onAsk()
                } label: {
                    Label(String(localized: "Ask About This"), systemImage: "sparkles")
                }
            }

            Button {
                onEdit()
            } label: {
                Label(String(localized: "Edit Details"), systemImage: "pencil")
            }

            // Only once lists exist — they are made from the wishlist screen,
            // and an empty submenu would be a dead end.
            if !repository.wishlists.isEmpty {
                Menu {
                    Picker(selection: wishlistBinding) {
                        Text("None").tag(UUID?.none)
                        ForEach(repository.sortedWishlists) { list in
                            Label(list.displayName, systemImage: list.symbolName)
                                .tag(UUID?.some(list.id))
                        }
                    } label: {
                        Text("Wishlist")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(localized: "Wishlist"), systemImage: "list.bullet")
                }
            }

            if let url = item.productURL {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        Label(String(localized: "Open in Safari"), systemImage: "safari")
                    }

                    ShareLink(item: url) {
                        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        UIPasteboard.general.url = url
                    } label: {
                        Label(String(localized: "Copy Link"), systemImage: "doc.on.doc")
                    }

                    if let onRefresh {
                        Button {
                            onRefresh()
                        } label: {
                            Label(String(localized: "Update from Store"), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
    }
}
