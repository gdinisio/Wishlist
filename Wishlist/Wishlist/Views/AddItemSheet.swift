//
//  AddItemSheet.swift
//  Wishlist
//
//  Paste a link, tap Find, check what came back, add it. Two fields, one of
//  them optional — everything else the app works out for itself.
//

import SwiftUI
import Foundation

struct AddItemSheet: View {
    var onOpenExistingItem: (WishlistItem.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.productLookup) private var lookup
    @Environment(WishlistRepository.self) private var repository
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppRouter.self) private var router

    @State private var urlText = ""
    @State private var nameText = ""
    @State private var phase: AddPhase = .input
    @State private var path: [AddRoute] = []
    @State private var draft = WishlistItem(name: "")
    @State private var warning: LookupError?
    @State private var duplicate: WishlistItem?
    @State private var progress = LookupProgress()
    @State private var lookupTask: Task<Void, Never>?
    @State private var isEnteringManually = false
    @State private var didAddManually = false
    @FocusState private var focusedField: Field?

    private nonisolated enum Field: Hashable {
        case url
        case name
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                linkSection
                nameSection
                statusSection
                manualSection
            }
            .navigationTitle(Text("Add Item"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .confirm:
                    LookupConfirmView(item: $draft, warning: warning) {
                        addDraft()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSearching {
                        ProgressView()
                    } else {
                        Button(primaryActionTitle) { startLookup() }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                    }
                }
            }
            .onSubmit { if canSubmit { startLookup() } }
            .onChange(of: isEnteringManually) { _, isPresented in
                // Dismiss the Add sheet only once the editor has closed, so the
                // two dismissals do not fight each other.
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
            if urlText.isEmpty { focusedField = .url }
        }
        .onDisappear { lookupTask?.cancel() }
    }

    // MARK: - Sections

    private var linkSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(String(localized: "https://"), text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .url)
                    .accessibilityLabel(Text("Product link"))

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        resetResult()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear link"))
                } else {
                    // The system paste control: no clipboard prompt, and it
                    // only appears when there is a link to paste.
                    PasteButton(payloadType: URL.self) { urls in
                        if let url = urls.first {
                            urlText = url.absoluteString
                            resetResult()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
        } header: {
            Text("Link")
        } footer: {
            Text("Paste a product link and Wishlist will find the name, price and picture.")
        }
    }

    private var nameSection: some View {
        Section {
            TextField(String(localized: "Item name"), text: $nameText)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .focused($focusedField, equals: .name)
        } header: {
            Text("Name")
        } footer: {
            Text(urlText.isEmpty
                 ? String(localized: "No link? Add it by name and fill in the details yourself.")
                 : String(localized: "Optional. Use this if you’d rather not keep the store’s wording."))
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isSearching {
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
                    dismiss()
                    onOpenExistingItem(existing.id)
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
                    Button(String(localized: "Try Again")) { startLookup() }
                }
                if error.suggestsSettings {
                    Button(String(localized: "Open Settings")) {
                        dismiss()
                        router.showSettings()
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
        } else if !settings.hasAnyAPIKey && looksLikeAmazon {
            Section {
                InlineMessage(
                    symbolName: "info.circle",
                    title: String(localized: "Reading the Amazon Page"),
                    message: String(localized: "This works, but Amazon sometimes blocks it. Amazon’s own API is free and more reliable — set it up in Settings."),
                    tint: .secondary
                )
                Button(String(localized: "Open Settings")) {
                    dismiss()
                    router.showSettings()
                }
            }
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

    private var isSearching: Bool {
        phase == .searching
    }

    private var canSubmit: Bool {
        !isSearching && (!urlText.trimmingCharacters(in: .whitespaces).isEmpty
            || !nameText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var primaryActionTitle: String {
        URLValidator.looksLikeURL(urlText)
            ? String(localized: "Find")
            : String(localized: "Add")
    }

    private var looksLikeAmazon: Bool {
        guard let link = try? URLValidator.validate(urlText) else { return false }
        return link.isAmazon
    }

    private var manualDraft: WishlistItem {
        var item = WishlistItem(name: nameText.trimmingCharacters(in: .whitespacesAndNewlines))
        if let link = try? URLValidator.validate(urlText) {
            item.productURL = link.canonicalURL
            item.retailer = link.retailer
        }
        return item
    }

    private func resetResult() {
        duplicate = nil
        warning = nil
        if case .failed = phase { phase = .input }
    }

    // MARK: - Lookup

    private func startLookup() {
        focusedField = nil
        lookupTask?.cancel()
        resetResult()
        phase = .searching
        progress.message = LookupStage.validating.message

        let credentials = settings.credentials
        let isOnline = network.isOnline
        let url = urlText
        let name = nameText
        let progressTracker = self.progress

        lookupTask = Task {
            do {
                let outcome = try await lookup.lookup(
                    urlText: url,
                    nameText: name,
                    credentials: credentials,
                    isOnline: isOnline,
                    onStage: { stage in
                        Task { @MainActor in progressTracker.message = stage.message }
                    }
                )
                guard !Task.isCancelled else { return }
                handle(outcome)
            } catch let error as LookupError {
                guard !Task.isCancelled, error != .cancelled else { return }
                phase = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(.providerUnavailable(provider: nil))
            }
        }
    }

    private func handle(_ outcome: LookupOutcome) {
        let item = outcome.item
        phase = .input
        warning = outcome.partialFailure
        draft = item

        if let existing = repository.existingItem(
            forURL: item.productURL,
            name: item.name,
            retailer: item.retailer
        ) {
            duplicate = existing
            return
        }
        path.append(.confirm)
    }

    private func addDraft() {
        repository.add(draft)
        dismiss()
    }
}

nonisolated enum AddPhase: Equatable {
    case input
    case searching
    case failed(LookupError)
}

nonisolated enum AddRoute: Hashable {
    case confirm
}

#Preview {
    AddItemSheet(onOpenExistingItem: { _ in })
        .withPreviewEnvironment()
}
