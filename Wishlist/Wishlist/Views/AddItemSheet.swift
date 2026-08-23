//
//  AddItemSheet.swift
//  Wishlist
//
//  One field. Paste a link or type a name — the app works out which it is
//  rather than asking, because the user already knows what they typed and
//  should not have to tell the form twice.
//
//  A name is searched on the storefront the user already shops at, and the
//  results are shown to be chosen from. Picking one runs the ordinary lookup
//  against that product's own page, so a name-added item is exactly as
//  verified as a link-added one.
//

import SwiftUI
import Foundation

/// What the Add sheet wants to happen once it has closed. Navigating while a
/// sheet is still dismissing drops the transition, so the intent is recorded
/// here and acted on by the presenting screen afterwards.
nonisolated enum AddItemExit: Equatable {
    case none
    case openItem(WishlistItem.ID)
    case openSettings
}

struct AddItemSheet: View {
    @Binding var exit: AddItemExit
    /// The list currently on screen. Something added while looking at "Tech"
    /// belongs on it without being asked.
    var wishlistID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.productLookup) private var lookup
    @Environment(\.productSearch) private var search
    @Environment(WishlistRepository.self) private var repository
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network

    @State private var queryText = ""
    @State private var colourText = ""
    @State private var sizeText = ""
    @State private var phase: AddPhase = .input
    @State private var path: [AddRoute] = []
    @State private var draft = WishlistItem(name: "")
    @State private var candidates: [ProductCandidate] = []
    @State private var warning: LookupError?
    @State private var duplicate: WishlistItem?
    @State private var progress = LookupProgress()
    @State private var workTask: Task<Void, Never>?
    @State private var isEnteringManually = false
    @State private var didAddManually = false
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                inputSection
                if !isLink { detailsSection }
                statusSection
                manualSection
            }
            .navigationTitle(Text("Add Item"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .candidates:
                    CandidatePicker(
                        candidates: candidates,
                        query: queryText,
                        onChoose: { choose($0) },
                        onAddByName: { isEnteringManually = true }
                    )
                case .confirm:
                    LookupConfirmView(item: $draft, warning: warning) { addDraft() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(primaryActionTitle) { start() }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
            .onSubmit { if canSubmit { start() } }
            .onChange(of: isEnteringManually) { _, isPresented in
                if !isPresented && didAddManually { dismiss() }
            }
            .sheet(isPresented: $isEnteringManually) {
                ItemEditorSheet(
                    mode: .draft(
                        manualDraft,
                        title: String(localized: "New Item"),
                        saveLabel: String(localized: "Add")
                    ),
                    onSave: { item in
                        repository.add(item)
                        didAddManually = true
                    }
                )
            }
        }
        .task {
            // A sheet's fields cannot take focus until it has finished
            // presenting; this is the standard short wait before asking.
            try? await Task.sleep(for: .milliseconds(400))
            if queryText.isEmpty { isQueryFocused = true }
        }
        .onDisappear { workTask?.cancel() }
    }

    // MARK: - Input

    private var inputSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(String(localized: "Link or name"), text: $queryText, axis: .vertical)
                    .lineLimit(1...3)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(isLink ? .never : .words)
                    .autocorrectionDisabled(isLink)
                    .submitLabel(.go)
                    .focused($isQueryFocused)
                    .accessibilityLabel(Text("Link or product name"))

                if !queryText.isEmpty {
                    Button {
                        queryText = ""
                        resetResult()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                } else {
                    // The system paste control: no clipboard prompt, and it
                    // only appears when there is a link to paste.
                    PasteButton(payloadType: URL.self) { urls in
                        if let url = urls.first {
                            queryText = url.absoluteString
                            resetResult()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
        } header: {
            Text("What do you want?")
        } footer: {
            Text(isLink
                 ? String(localized: "Wishlist will read the page for the name, price and picture.")
                 : String(localized: "Paste a link, or just type what it’s called and Wishlist will look it up."))
        }
    }

    /// Only shown for a name, because a link already points at one exact
    /// variant — asking for its colour would be asking twice.
    private var detailsSection: some View {
        Section {
            TextField(String(localized: "Colour"), text: $colourText)
                .textInputAutocapitalization(.words)
            TextField(String(localized: "Size"), text: $sizeText)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Details (Optional)")
        } footer: {
            Text("Narrows the search, and is kept with the item so you know which one you meant.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isWorking {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progress.message ?? String(localized: "Looking…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        } else if let existing = duplicate {
            Section {
                InlineMessage(
                    symbolName: "exclamationmark.circle",
                    title: String(localized: "Already on Your Wishlist"),
                    message: String(localized: "“\(existing.displayName)” is already saved."),
                    tint: .orange
                )
                Button(String(localized: "View Saved Item")) {
                    exit = .openItem(existing.id)
                    dismiss()
                }
                Button(String(localized: "Add Anyway")) {
                    duplicate = nil
                    path.append(.confirm)
                }
            }
        } else if case .failed(let error) = phase {
            Section {
                InlineMessage(
                    symbolName: error.symbolName,
                    title: error.title,
                    message: error.guidance,
                    tint: .orange
                )
                if error.isRetryable {
                    Button(String(localized: "Try Again")) { start() }
                }
                if error.suggestsSettings {
                    Button(String(localized: "Open Settings")) {
                        exit = .openSettings
                        dismiss()
                    }
                }
                if error.allowsManualEntry {
                    Button(String(localized: "Add Details Manually")) {
                        isEnteringManually = true
                    }
                }
            }
        } else if !network.isOnline {
            Section { OfflineNotice() }
        }
    }

    private var manualSection: some View {
        Section {
            Button {
                isEnteringManually = true
            } label: {
                Label(String(localized: "Enter Details Manually"), systemImage: "square.and.pencil")
            }
        }
    }

    // MARK: - State

    private var isWorking: Bool { phase == .searching }

    private var isLink: Bool { URLValidator.looksLikeURL(queryText) }

    private var canSubmit: Bool {
        !isWorking && !queryText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var primaryActionTitle: String {
        isLink ? String(localized: "Fetch") : String(localized: "Search")
    }

    private var manualDraft: WishlistItem {
        var item = WishlistItem(name: isLink ? "" : queryText.trimmingCharacters(in: .whitespacesAndNewlines))
        applyDetails(to: &item)
        item.wishlistID = wishlistID
        if let link = try? URLValidator.validate(queryText) {
            item.productURL = link.canonicalURL
            item.retailer = link.retailer
        }
        return item
    }

    /// The colour and size the user gave are theirs, not the store's, so they
    /// survive whatever the lookup returns.
    private func applyDetails(to item: inout WishlistItem) {
        let colour = colourText.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.colour = colour.isEmpty ? nil : colour
        item.size = size.isEmpty ? nil : size
        item.wishlistID = wishlistID
    }

    private func resetResult() {
        duplicate = nil
        warning = nil
        candidates = []
        if case .failed = phase { phase = .input }
    }

    // MARK: - Work

    private func start() {
        isQueryFocused = false
        workTask?.cancel()
        resetResult()
        phase = .searching

        if isLink {
            runLookup(for: queryText, applyingDetails: true)
        } else {
            runSearch()
        }
    }

    private func runSearch() {
        progress.message = String(localized: "Searching…")

        let query = ProductSearchService.query(
            name: queryText,
            colour: colourText,
            size: sizeText
        )
        let marketplace = settings.amazonMarketplace
        let isOnline = network.isOnline

        workTask = Task {
            guard isOnline else {
                phase = .failed(.offline)
                return
            }
            do {
                let found = try await search.search(query: query, marketplace: marketplace)
                guard !Task.isCancelled else { return }
                phase = .input
                guard !found.isEmpty else {
                    phase = .failed(.noProductData)
                    return
                }
                candidates = found
                path.append(.candidates)
            } catch let error as LookupError {
                guard !Task.isCancelled, error != .cancelled else { return }
                phase = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(.providerUnavailable(provider: nil))
            }
        }
    }

    /// Chosen from the results, this runs the normal chain against the
    /// product's own page — the same path a pasted link takes.
    private func choose(_ candidate: ProductCandidate) {
        workTask?.cancel()
        phase = .searching
        runLookup(for: candidate.productURL.absoluteString, applyingDetails: true)
    }

    private func runLookup(for text: String, applyingDetails: Bool) {
        progress.message = LookupStage.validating.message

        let credentials = settings.credentials
        let isOnline = network.isOnline
        let progressTracker = self.progress

        workTask = Task {
            do {
                let outcome = try await lookup.lookup(
                    urlText: text,
                    nameText: nil,
                    credentials: credentials,
                    isOnline: isOnline,
                    onStage: { stage in
                        Task { @MainActor in progressTracker.message = stage.message }
                    }
                )
                guard !Task.isCancelled else { return }
                handle(outcome, applyingDetails: applyingDetails)
            } catch let error as LookupError {
                guard !Task.isCancelled, error != .cancelled else { return }
                phase = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(.providerUnavailable(provider: nil))
            }
        }
    }

    private func handle(_ outcome: LookupOutcome, applyingDetails: Bool) {
        var item = outcome.item
        if applyingDetails { applyDetails(to: &item) }

        phase = .input
        warning = outcome.partialFailure
        draft = item

        if let existing = repository.existingItem(
            forURL: item.productURL,
            name: item.name,
            retailer: item.retailer
        ) {
            duplicate = existing
            // Surfaced on the input screen, so step back to it.
            path = []
            return
        }
        path.append(.confirm)
    }

    private func addDraft() {
        repository.add(draft)
        dismiss()
    }
}

/// The results of a search by name. A picture and a price are what actually
/// let someone recognise the thing they meant.
private struct CandidatePicker: View {
    let candidates: [ProductCandidate]
    let query: String
    var onChoose: (ProductCandidate) -> Void
    var onAddByName: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        onChoose(candidate)
                    } label: {
                        CandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Results for “\(query)”")
                    .textCase(nil)
            } footer: {
                Text("Choosing one reads its own page for the price, picture and details.")
            }

            Section {
                Button {
                    onAddByName()
                } label: {
                    Label(String(localized: "None of These — Add by Name"), systemImage: "square.and.pencil")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Choose the Right One"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CandidateRow: View {
    let candidate: ProductCandidate

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 54

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: candidate.imageURL, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let price = candidate.price {
                    Text(price.formatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text("No price shown")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [candidate.name]
        if let price = candidate.price {
            parts.append(price.accessibleDescription)
        } else {
            parts.append(String(localized: "no price shown"))
        }
        return parts.joined(separator: ", ")
    }
}

nonisolated enum AddPhase: Equatable {
    case input
    case searching
    case failed(LookupError)
}

nonisolated enum AddRoute: Hashable {
    case candidates
    case confirm
}

#Preview {
    AddItemSheet(exit: .constant(.none), wishlistID: nil)
        .withPreviewEnvironment()
}
