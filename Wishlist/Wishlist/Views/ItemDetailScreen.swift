//
//  ItemDetailScreen.swift
//  Wishlist
//
//  Everything known about one item, with the action you are most likely to
//  want kept in view at the bottom of the screen rather than buried in a menu.
//

import SwiftUI
import Foundation

struct ItemDetailScreen: View {
    let itemID: WishlistItem.ID

    @Environment(WishlistRepository.self) private var repository
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var notesDraft = ""
    @State private var isEditing = false
    @State private var isRefreshing = false
    @State private var refreshError: LookupError?
    @State private var isConfirmingDelete = false
    @State private var isDescriptionExpanded = false
    @State private var isViewingImage = false
    @State private var isAsking = false

    var body: some View {
        Group {
            if let item = repository.item(id: itemID) {
                detail(for: item)
            } else {
                ContentUnavailableView {
                    Label(String(localized: "Item Removed"), systemImage: "trash")
                } description: {
                    Text("This item is no longer on your wishlist.")
                }
            }
        }
        .task(id: itemID) {
            notesDraft = repository.item(id: itemID)?.notes ?? ""
        }
        .onChange(of: repository.item(id: itemID) == nil) { _, hasGone in
            // Covers deletion from here, from a swipe on the list behind, or
            // from anywhere else: the screen leaves rather than sitting on a
            // record that no longer exists.
            if hasGone { dismiss() }
        }
    }

    // MARK: - Detail

    private func detail(for item: WishlistItem) -> some View {
        List {
            heroSection(item)
            statusSection(item)
            detailsSection(item)
            linkSection(item)
            descriptionSection(item)
            notesSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(item.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            primaryAction(for: item)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAsking = true
                } label: {
                    Label(String(localized: "Ask About This"), systemImage: "sparkles")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ItemActionsMenu(
                        item: item,
                        onEdit: { isEditing = true },
                        onDelete: { requestDeletion() },
                        onRefresh: { refresh() },
                        onAsk: { isAsking = true }
                    )
                } label: {
                    Label(String(localized: "More"), systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ItemEditorSheet(mode: .edit(item))
        }
        .sheet(isPresented: $isAsking) {
            AskAssistantSheet(item: item)
        }
        .fullScreenCover(isPresented: $isViewingImage) {
            if let url = item.imageURL {
                ProductImageViewer(url: url, title: item.displayName)
            }
        }
        .confirmationDialog(
            Text("Delete “\(item.displayName)”?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                repository.delete(id: item.id)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This permanently removes the item and its history.")
        }
        .onChange(of: notesDraft) { _, newValue in
            guard let current = repository.item(id: itemID) else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != (current.notes ?? "") else { return }
            repository.setNotes(newValue, for: itemID)
        }
        .sensoryFeedback(trigger: item.status) { _, newValue in
            guard settings.hapticsEnabled else { return nil }
            return newValue == .obtained ? .success : .selection
        }
    }

    // MARK: - Sections

    private func heroSection(_ item: WishlistItem) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    if item.imageURL != nil { isViewingImage = true }
                } label: {
                    RemoteImage(url: item.imageURL, contentMode: .fit, maxPixelSize: 520)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item.imageURL == nil)
                .accessibilityLabel(imageAccessibilityLabel(item))
                .accessibilityHint(item.imageURL == nil ? Text("") : Text("Opens the photo full screen"))

                VStack(alignment: .leading, spacing: 6) {
                    if let brand = item.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .accessibilityLabel(Text("Brand, \(brand)"))
                    }
                    Text(item.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        }
    }

    private func statusSection(_ item: WishlistItem) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                if let price = item.price {
                    Text(price.formatted)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel(Text("Current price, \(price.accessibleDescription)"))
                } else {
                    Text("Price unavailable")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if isRefreshing {
                    ProgressView()
                        .accessibilityLabel(Text("Checking price"))
                }
            }

            if let change = item.priceChange {
                PriceChangeLabel(change: change, isCompact: false)
            }

            AvailabilityBadge(availability: item.availability)

            budgetStanding(item)

            if let error = refreshError {
                InlineMessage(
                    symbolName: error.symbolName,
                    title: error.title,
                    message: error.guidance,
                    tint: .orange
                )
            }
        } footer: {
            if let footer = provenanceFooter(item) {
                Text(footer)
            }
        }
    }

    /// Where this item sits against what the user has to spend. Shown only
    /// when both a budget and a comparable price exist.
    @ViewBuilder
    private func budgetStanding(_ item: WishlistItem) -> some View {
        if let budget = settings.availableToSpend, item.price != nil {
            if let over = item.amountOver(budget) {
                Label(
                    String(localized: "\(over.formatted) more than you have to spend"),
                    systemImage: "exclamationmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            } else if item.fits(within: budget) {
                Label(
                    String(localized: "Within your \(budget.formatted)"),
                    systemImage: "checkmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.green)
            }
        }
    }

    private func detailsSection(_ item: WishlistItem) -> some View {
        Section {
            if let retailer = item.displayRetailer {
                LabeledContent(String(localized: "Store"), value: retailer)
            }
            if let category = item.category, !category.isEmpty {
                LabeledContent(String(localized: "Category"), value: category)
            }
            if let variant = item.variantSummary {
                LabeledContent(String(localized: "Variant"), value: variant)
            }
            if let collection = item.collectionName, !collection.isEmpty {
                LabeledContent(String(localized: "Collection"), value: collection)
            }
            // Shown whenever the displayed name is a shortened form, so the
            // store's own wording is never hidden.
            if let fullName = item.fullName, !fullName.isEmpty, fullName != item.name {
                LabeledContent(String(localized: "Full Title")) {
                    Text(fullName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }
            if let original = item.originalPrice, item.priceChange != nil {
                LabeledContent(String(localized: "When Added"), value: original.formatted)
            }
            LabeledContent(String(localized: "Added"), value: DateText.friendly(item.dateAdded))
            if let obtained = item.dateObtained {
                LabeledContent(String(localized: "Obtained"), value: DateText.friendly(obtained))
            }
        } header: {
            Text("Details")
        }
    }

    @ViewBuilder
    private func linkSection(_ item: WishlistItem) -> some View {
        if let url = item.productURL {
            Section {
                Button {
                    openURL(url)
                } label: {
                    HStack {
                        Label(String(localized: "Open in Safari"), systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }

                ShareLink(item: url) {
                    Label(String(localized: "Share Link"), systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Link")
            } footer: {
                Text(url.host() ?? url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(_ item: WishlistItem) -> some View {
        if let details = item.details, !details.isEmpty {
            Section {
                Text(details)
                    .font(.subheadline)
                    .lineLimit(isDescriptionExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if details.count > 220 {
                    Button(isDescriptionExpanded
                           ? String(localized: "Show Less")
                           : String(localized: "Show More")) {
                        isDescriptionExpanded.toggle()
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Description")
            }
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                String(localized: "Add a note"),
                text: $notesDraft,
                axis: .vertical
            )
            .lineLimit(1...6)
            .accessibilityLabel(Text("Notes"))
        } header: {
            Text("Notes")
        } footer: {
            Text("Only you see this — size, colour, who it's for.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                requestDeletion()
            } label: {
                Label(String(localized: "Delete Item"), systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Primary action

    private func primaryAction(for item: WishlistItem) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if item.isObtained {
                    repository.returnToWishlist(id: item.id)
                } else {
                    repository.markObtained(id: item.id)
                }
            } label: {
                Label(
                    item.isObtained
                        ? String(localized: "Move Back to Wishlist")
                        : String(localized: "Mark as Obtained"),
                    systemImage: item.isObtained ? "arrow.uturn.backward" : "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(item.isObtained ? .gray : .accentColor)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    // MARK: - Helpers

    private func imageAccessibilityLabel(_ item: WishlistItem) -> Text {
        item.imageURL == nil
            ? Text("No product image available")
            : Text("Photo of \(item.displayName)")
    }

    /// "Details from Amazon · Checked 2 hours ago" — where the numbers came
    /// from, and how fresh they are.
    private func provenanceFooter(_ item: WishlistItem) -> String? {
        var parts: [String] = []
        if !item.sources.isEmpty {
            parts.append(String(localized: "Details from \(item.sources.joined(separator: ", "))"))
        }
        if let refreshed = item.dateRefreshed {
            parts.append(String(localized: "Checked \(DateText.friendly(refreshed))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func requestDeletion() {
        if settings.confirmBeforeDeleting {
            isConfirmingDelete = true
        } else {
            repository.delete(id: itemID)
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        Task {
            let error = await repository.refresh(id: itemID)
            isRefreshing = false
            refreshError = error
        }
    }
}

#Preview {
    NavigationStack {
        ItemDetailScreen(itemID: WishlistItem.samples[0].id)
    }
    .withPreviewEnvironment()
}
