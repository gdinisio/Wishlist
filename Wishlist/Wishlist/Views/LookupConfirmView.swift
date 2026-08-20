//
//  LookupConfirmView.swift
//  Wishlist
//
//  The review step. It shows exactly what was found and, just as plainly, what
//  was not — an empty field is labelled, never quietly filled in.
//

import SwiftUI
import Foundation

struct LookupConfirmView: View {
    @Binding var item: WishlistItem
    var warning: LookupError?
    var onAdd: () -> Void

    @State private var isEditing = false

    var body: some View {
        List {
            previewSection
            noticeSection
            detailsSection
            editSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Review"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    onAdd()
                } label: {
                    Label(String(localized: "Add to Wishlist"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .disabled(item.displayName.isEmpty)
            }
            .background(.bar)
        }
        .sheet(isPresented: $isEditing) {
            ItemEditorSheet(
                mode: .draft(
                    item,
                    title: String(localized: "Edit Details"),
                    saveLabel: String(localized: "Done")
                ),
                onSave: { edited in item = edited }
            )
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImage(url: item.imageURL, contentMode: .fit, maxPixelSize: 460)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(item.imageURL == nil
                                        ? Text("No product image found")
                                        : Text("Photo of \(item.displayName)"))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if let price = item.price {
                            Text(price.formatted)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        } else {
                            Text("Price not found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if item.availability != .unknown {
                            AvailabilityBadge(availability: item.availability, isCompact: true)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        } footer: {
            if !item.sources.isEmpty {
                Text("Details from \(item.sources.joined(separator: ", "))")
            }
        }
    }

    @ViewBuilder
    private var noticeSection: some View {
        if let warning {
            Section {
                InlineMessage(
                    symbolName: warning.symbolName,
                    title: String(localized: "Some Details Are Missing"),
                    message: warning.guidance,
                    tint: .orange
                )
            }
        } else if !item.missingFields.isEmpty {
            Section {
                InlineMessage(
                    symbolName: "questionmark.circle",
                    title: String(localized: "Some Details Are Missing"),
                    message: missingMessage,
                    tint: .secondary
                )
            }
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent(String(localized: "Store")) {
                valueText(item.displayRetailer)
            }
            LabeledContent(String(localized: "Price")) {
                valueText(item.price?.formatted)
            }
            LabeledContent(String(localized: "Availability")) {
                valueText(item.availability == .unknown ? nil : item.availability.label)
            }
            if let brand = item.brand {
                LabeledContent(String(localized: "Brand"), value: brand)
            }
            if let category = item.category {
                LabeledContent(String(localized: "Category"), value: category)
            }
            if let url = item.productURL {
                LabeledContent(String(localized: "Link")) {
                    Text(url.host() ?? url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Details")
        }
    }

    private var editSection: some View {
        Section {
            Button {
                isEditing = true
            } label: {
                Label(String(localized: "Edit Details"), systemImage: "pencil")
            }
        } footer: {
            Text("You can change any of this now, or at any time from the item.")
        }
    }

    // MARK: - Helpers

    /// Missing values read as "Not found" rather than as blank space, so the
    /// user can tell the difference between "nothing there" and "not checked".
    @ViewBuilder
    private func valueText(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(value)
                .foregroundStyle(.secondary)
        } else {
            Text("Not found")
                .foregroundStyle(.tertiary)
        }
    }

    private var missingMessage: String {
        let fields = item.missingFields
        let list = fields.formatted(.list(type: .and))
        return String(localized: "Wishlist couldn’t find the \(list). You can add it yourself, or leave it blank.")
    }
}

#Preview {
    NavigationStack {
        LookupConfirmView(item: .constant(WishlistItem.sample), warning: nil) {}
    }
    .withPreviewEnvironment()
}
