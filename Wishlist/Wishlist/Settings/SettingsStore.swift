//
//  SettingsStore.swift
//  Wishlist
//
//  Everything the user has configured, in one observable place: credentials in
//  the Keychain, preferences in user defaults. Entered once and remembered —
//  no screen ever asks for a key twice.
//
//  Persistence is automatic. Rather than repeating a write in every setter, the
//  store observes itself and saves shortly after any change, so a value typed
//  anywhere in the app is durable without the UI having to remember to save it.
//

import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    // MARK: - Credentials (stored in the Keychain)

    var amazonAccessKey: String = ""
    var amazonSecretKey: String = ""
    var amazonPartnerTag: String = ""
    var rainforestKey: String = ""
    var microlinkKey: String = ""

    // MARK: - Preferences (stored in user defaults)

    var amazonMarketplace: AmazonMarketplace = .unitedStates
    /// Reading the product page needs no key, so it is on unless turned off.
    var allowsWebPageLookup: Bool = true
    var refreshOnLaunch: Bool = true
    var confirmBeforeDeleting: Bool = true
    var hapticsEnabled: Bool = true
    var sortOrder: WishlistSortOrder = .dateAddedDescending

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults

        amazonAccessKey = keychain.string(forKey: CredentialKey.amazonAccessKey) ?? ""
        amazonSecretKey = keychain.string(forKey: CredentialKey.amazonSecretKey) ?? ""
        amazonPartnerTag = keychain.string(forKey: CredentialKey.amazonPartnerTag) ?? ""
        rainforestKey = keychain.string(forKey: CredentialKey.rainforestKey) ?? ""
        microlinkKey = keychain.string(forKey: CredentialKey.microlinkKey) ?? ""

        amazonMarketplace = defaults.string(forKey: Key.marketplace)
            .flatMap(AmazonMarketplace.init(rawValue:))
            ?? SettingsStore.defaultMarketplace()
        allowsWebPageLookup = defaults.object(forKey: Key.webPageLookup) as? Bool ?? true
        refreshOnLaunch = defaults.object(forKey: Key.refreshOnLaunch) as? Bool ?? true
        confirmBeforeDeleting = defaults.object(forKey: Key.confirmDelete) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        sortOrder = defaults.string(forKey: Key.sortOrder)
            .flatMap(WishlistSortOrder.init(rawValue:))
            ?? .dateAddedDescending

        observeChanges()
    }

    // MARK: - Derived

    /// A snapshot handed to the lookup pipeline. Providers receive a value
    /// type, never a live reference to app settings.
    var credentials: LookupCredentials {
        LookupCredentials(
            amazonAccessKey: amazonAccessKey,
            amazonSecretKey: amazonSecretKey,
            amazonPartnerTag: amazonPartnerTag,
            amazonMarketplace: amazonMarketplace,
            rainforestKey: rainforestKey,
            microlinkKey: microlinkKey,
            allowsWebPageLookup: allowsWebPageLookup
        )
    }

    /// True when at least one keyed provider is set up. Drives the gentle hint
    /// on the Add screen instead of an error after the fact.
    var hasAnyAPIKey: Bool {
        credentials.hasAmazonPAAPI || credentials.hasRainforest
    }

    func clearAllCredentials() {
        amazonAccessKey = ""
        amazonSecretKey = ""
        amazonPartnerTag = ""
        rainforestKey = ""
        microlinkKey = ""
    }

    // MARK: - Automatic persistence

    /// Re-arms itself after every change, so a single, debounced write follows
    /// any mutation from anywhere in the app.
    private func observeChanges() {
        withObservationTracking {
            _ = amazonAccessKey
            _ = amazonSecretKey
            _ = amazonPartnerTag
            _ = rainforestKey
            _ = microlinkKey
            _ = amazonMarketplace
            _ = allowsWebPageLookup
            _ = refreshOnLaunch
            _ = confirmBeforeDeleting
            _ = hapticsEnabled
            _ = sortOrder
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeChanges()
                self?.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            // Typing a key should not mean a Keychain write per keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    /// Writes immediately. Called when the app leaves the foreground.
    func persistNow() {
        persistTask?.cancel()
        persist()
    }

    private func persist() {
        keychain.set(amazonAccessKey, forKey: CredentialKey.amazonAccessKey)
        keychain.set(amazonSecretKey, forKey: CredentialKey.amazonSecretKey)
        keychain.set(amazonPartnerTag, forKey: CredentialKey.amazonPartnerTag)
        keychain.set(rainforestKey, forKey: CredentialKey.rainforestKey)
        keychain.set(microlinkKey, forKey: CredentialKey.microlinkKey)

        defaults.set(amazonMarketplace.rawValue, forKey: Key.marketplace)
        defaults.set(allowsWebPageLookup, forKey: Key.webPageLookup)
        defaults.set(refreshOnLaunch, forKey: Key.refreshOnLaunch)
        defaults.set(confirmBeforeDeleting, forKey: Key.confirmDelete)
        defaults.set(hapticsEnabled, forKey: Key.haptics)
        defaults.set(sortOrder.rawValue, forKey: Key.sortOrder)
    }

    /// Start from the storefront that matches the user's region, so a UK user
    /// is not asked to pick "United Kingdom" out of twenty-one options.
    private static func defaultMarketplace() -> AmazonMarketplace {
        guard let region = Locale.current.region?.identifier else { return .unitedStates }
        let byRegion: [String: AmazonMarketplace] = [
            "GB": .unitedKingdom, "US": .unitedStates, "DE": .germany, "FR": .france,
            "IT": .italy, "ES": .spain, "NL": .netherlands, "SE": .sweden,
            "PL": .poland, "BE": .belgium, "IE": .ireland, "CA": .canada,
            "MX": .mexico, "BR": .brazil, "JP": .japan, "AU": .australia,
            "SG": .singapore, "IN": .india, "AE": .unitedArabEmirates,
            "SA": .saudiArabia, "TR": .turkey
        ]
        return byRegion[region] ?? .unitedStates
    }

    private enum Key {
        static let marketplace = "settings.amazonMarketplace"
        static let webPageLookup = "settings.allowsWebPageLookup"
        static let refreshOnLaunch = "settings.refreshOnLaunch"
        static let confirmDelete = "settings.confirmBeforeDeleting"
        static let haptics = "settings.hapticsEnabled"
        static let sortOrder = "settings.sortOrder"
    }
}
