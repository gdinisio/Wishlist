//
//  SettingsScreen.swift
//  Wishlist
//
//  Set up once, never asked again. Keys live in the Keychain; everything here
//  is grouped by what it affects, in the order it matters.
//

import SwiftUI
import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WishlistRepository.self) private var repository

    @State private var cacheSize: Int = 0
    @State private var isConfirmingItemDeletion = false
    @State private var isConfirmingKeyRemoval = false
    @State private var didClearCache = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AmazonSettingsView()
                    } label: {
                        ProviderRow(
                            title: String(localized: "Amazon Product Advertising"),
                            symbolName: "cart",
                            isConfigured: settings.credentials.hasAmazonPAAPI,
                            detail: settings.credentials.hasAmazonPAAPI
                                ? settings.amazonMarketplace.displayName
                                : String(localized: "Optional")
                        )
                    }

                    NavigationLink {
                        MicrolinkSettingsView()
                    } label: {
                        ProviderRow(
                            title: String(localized: "Microlink"),
                            symbolName: "link",
                            isConfigured: !settings.microlinkKey.isEmpty,
                            detail: String(localized: "Optional")
                        )
                    }
                } header: {
                    Text("Product Lookup")
                } footer: {
                    Text("Every service Wishlist uses is free. It tries them in order: Amazon’s own API for Amazon links, then the store’s product page, then Microlink for pages that refuse to be read. Only the Amazon API needs a key, and it works without one. Keys are stored in your device’s Keychain and are only ever sent to the service they belong to.")
                }

                Section {
                    Toggle(isOn: $settings.allowsWebPageLookup) {
                        Label(String(localized: "Read Product Pages"), systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("Reads the details a store publishes on its own product page, including Amazon’s. Free, needs no key, and works for stores Wishlist has no API for.")
                }

                Section {
                    Picker(selection: $settings.amazonMarketplace) {
                        ForEach(AmazonMarketplace.allCases) { marketplace in
                            Text(marketplace.displayName).tag(marketplace)
                        }
                    } label: {
                        Label(String(localized: "Amazon Store"), systemImage: "globe")
                    }
                } footer: {
                    Text("Used when you add an item by name. Links always use the store they point at.")
                }

                Section {
                    Toggle(isOn: $settings.refreshOnLaunch) {
                        Label(String(localized: "Refresh Prices on Open"), systemImage: "arrow.clockwise")
                    }
                    Toggle(isOn: $settings.confirmBeforeDeleting) {
                        Label(String(localized: "Confirm Before Deleting"), systemImage: "trash")
                    }
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label(String(localized: "Haptic Feedback"), systemImage: "iphone.radiowaves.left.and.right")
                    }
                } header: {
                    Text("Behaviour")
                }

                Section {
                    LabeledContent(String(localized: "Image Cache"), value: DateText.byteCount(cacheSize))
                    Button {
                        clearCache()
                    } label: {
                        Text(didClearCache ? String(localized: "Cache Cleared") : String(localized: "Clear Image Cache"))
                    }
                    .disabled(cacheSize == 0 || didClearCache)

                    ShareLink(
                        item: exportDocument,
                        preview: SharePreview(String(localized: "Wishlist"))
                    ) {
                        Label(String(localized: "Export Wishlist"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(repository.items.isEmpty)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Your wishlist is stored on this device. Exporting saves a copy as a JSON file.")
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingKeyRemoval = true
                    } label: {
                        Text("Remove Saved API Keys")
                    }
                    Button(role: .destructive) {
                        isConfirmingItemDeletion = true
                    } label: {
                        Text("Delete All Items")
                    }
                    .disabled(repository.items.isEmpty)
                }

                Section {
                    LabeledContent(String(localized: "Version"), value: Self.versionString)
                } header: {
                    Text("About")
                } footer: {
                    Text("Wishlist never invents product information. If a price or an image can’t be retrieved, it says so rather than showing a guess.")
                }
            }
            .navigationTitle(Text("Settings"))
            .task { await loadCacheSize() }
            .confirmationDialog(
                Text("Delete all items?"),
                isPresented: $isConfirmingItemDeletion,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete All"), role: .destructive) {
                    repository.deleteAll()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("This removes everything on your wishlist and everything you’ve obtained. It can’t be undone.")
            }
            .confirmationDialog(
                Text("Remove saved API keys?"),
                isPresented: $isConfirmingKeyRemoval,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove Keys"), role: .destructive) {
                    settings.clearAllCredentials()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Lookups will fall back to reading product pages until you add them again.")
            }
        }
    }

    // MARK: - Helpers

    private var exportDocument: WishlistExport {
        WishlistExport(items: repository.items)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func loadCacheSize() async {
        cacheSize = await ImageLoader.shared.cacheSize()
    }

    private func clearCache() {
        Task {
            await ImageLoader.shared.clearCache()
            ImageMemoryCache.shared.removeAll()
            cacheSize = 0
            didClearCache = true
        }
    }
}

/// A settings row that states, without needing a colour, whether a provider is
/// ready to use.
struct ProviderRow: View {
    let title: String
    let symbolName: String
    let isConfigured: Bool
    let detail: String?

    var body: some View {
        HStack {
            Label(title, systemImage: symbolName)
            Spacer(minLength: 12)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), \(statusText)"))
    }

    private var statusText: String {
        if isConfigured {
            return detail ?? String(localized: "Set up")
        }
        return detail ?? String(localized: "Not set up")
    }
}

/// The wishlist as a shareable JSON document.
nonisolated struct WishlistExport: Transferable {
    var items: [WishlistItem]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try WishlistCoder.makeEncoder().encode(WishlistArchive(items: export.items))
        }
        .suggestedFileName("Wishlist.json")
    }
}

#Preview {
    SettingsScreen().withPreviewEnvironment()
}
