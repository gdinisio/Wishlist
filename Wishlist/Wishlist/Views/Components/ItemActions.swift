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

    @Environment(WishlistRepository.self) private var repository
    @Environment(\.openURL) private var openURL

    /// Writes straight through to the store, so the menu shows the current
    /// membership with a checkmark and changing it is one tap.
    private var collectionBinding: Binding<String?> {
        Binding(
            get: { item.collectionName },
            set: { repository.setCollection($0, for: item.id) }
        )
    }

    var body: some View {
        Group {
            if item.isObtained {
                Button {
                    repository.returnToWishlist(id: item.id)
                } label: {
                    Label(String(localized: "Move to Wishlist"), systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    repository.markObtained(id: item.id)
                } label: {
                    Label(String(localized: "Mark as Obtained"), systemImage: "checkmark.circle")
                }
            }

            Button {
                onEdit()
            } label: {
                Label(String(localized: "Edit Details"), systemImage: "pencil")
            }

            // Only once collections exist — the editor is where the first one
            // gets made, and an empty submenu would be a dead end.
            if !repository.collectionNames.isEmpty {
                Menu {
                    Picker(selection: collectionBinding) {
                        Text("None").tag(String?.none)
                        ForEach(repository.collectionNames, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    } label: {
                        Text("Collection")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(localized: "Collection"), systemImage: "folder")
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
                            Label(String(localized: "Refresh Price"), systemImage: "arrow.clockwise")
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
