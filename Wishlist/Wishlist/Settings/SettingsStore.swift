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
    var microlinkKey: String = ""
    var claudeKey: String = ""
    var groqKey: String = ""

    // MARK: - Preferences (stored in user defaults)

    var amazonMarketplace: AmazonMarketplace = .unitedStates
    /// Reading the product page needs no key, so it is on unless turned off.
    var allowsWebPageLookup: Bool = true
    var refreshOnLaunch: Bool = true
    var confirmBeforeDeleting: Bool = true
    var hapticsEnabled: Bool = true
    var sortOrder: WishlistSortOrder = .dateAddedDescending

    // MARK: - Language model assistance (off unless turned on)

    var intelligenceProvider: IntelligenceProvider = .off
    var claudeModel: ClaudeModel = .opus5
    var groqModel: String = IntelligenceSettings.defaultGroqModel
    var readsDifficultPages: Bool = true
    var shortensTitles: Bool = true
    var suggestsCategories: Bool = true

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults

        amazonAccessKey = keychain.string(forKey: CredentialKey.amazonAccessKey) ?? ""
        amazonSecretKey = keychain.string(forKey: CredentialKey.amazonSecretKey) ?? ""
        amazonPartnerTag = keychain.string(forKey: CredentialKey.amazonPartnerTag) ?? ""
        microlinkKey = keychain.string(forKey: CredentialKey.microlinkKey) ?? ""
        claudeKey = keychain.string(forKey: CredentialKey.claudeKey) ?? ""
        groqKey = keychain.string(forKey: CredentialKey.groqKey) ?? ""

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

        intelligenceProvider = defaults.string(forKey: Key.intelligenceProvider)
            .flatMap(IntelligenceProvider.init(rawValue:))
            ?? .off
        claudeModel = defaults.string(forKey: Key.claudeModel)
            .flatMap(ClaudeModel.init(rawValue:))
            ?? .opus5
        groqModel = defaults.string(forKey: Key.groqModel) ?? IntelligenceSettings.defaultGroqModel
        readsDifficultPages = defaults.object(forKey: Key.readsDifficultPages) as? Bool ?? true
        shortensTitles = defaults.object(forKey: Key.shortensTitles) as? Bool ?? true
        suggestsCategories = defaults.object(forKey: Key.suggestsCategories) as? Bool ?? true

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
            microlinkKey: microlinkKey,
            allowsWebPageLookup: allowsWebPageLookup,
            intelligence: intelligence
        )
    }

    /// The language-model configuration, as a value the pipeline can carry.
    var intelligence: IntelligenceSettings {
        IntelligenceSettings(
            provider: intelligenceProvider,
            claudeKey: claudeKey,
            claudeModel: claudeModel,
            groqKey: groqKey,
            groqModel: groqModel,
            readsDifficultPages: readsDifficultPages,
            shortensTitles: shortensTitles,
            suggestsCategories: suggestsCategories
        )
    }

    /// True when the Amazon API is set up. Drives the gentle hint on the Add
    /// screen instead of an error after the fact.
    var hasAnyAPIKey: Bool {
        credentials.hasAmazonPAAPI
    }

    func clearAllCredentials() {
        amazonAccessKey = ""
        amazonSecretKey = ""
        amazonPartnerTag = ""
        microlinkKey = ""
        claudeKey = ""
        groqKey = ""
    }

    // MARK: - Automatic persistence

    /// Re-arms itself after every change, so a single, debounced write follows
    /// any mutation from anywhere in the app.
    private func observeChanges() {
        withObservationTracking {
            _ = amazonAccessKey
            _ = amazonSecretKey
            _ = amazonPartnerTag
            _ = microlinkKey
            _ = claudeKey
            _ = groqKey
            _ = intelligenceProvider
            _ = claudeModel
            _ = groqModel
            _ = readsDifficultPages
            _ = shortensTitles
            _ = suggestsCategories
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
        keychain.set(microlinkKey, forKey: CredentialKey.microlinkKey)
        keychain.set(claudeKey, forKey: CredentialKey.claudeKey)
        keychain.set(groqKey, forKey: CredentialKey.groqKey)

        defaults.set(amazonMarketplace.rawValue, forKey: Key.marketplace)
        defaults.set(allowsWebPageLookup, forKey: Key.webPageLookup)
        defaults.set(refreshOnLaunch, forKey: Key.refreshOnLaunch)
        defaults.set(confirmBeforeDeleting, forKey: Key.confirmDelete)
        defaults.set(hapticsEnabled, forKey: Key.haptics)
        defaults.set(sortOrder.rawValue, forKey: Key.sortOrder)
        defaults.set(intelligenceProvider.rawValue, forKey: Key.intelligenceProvider)
        defaults.set(claudeModel.rawValue, forKey: Key.claudeModel)
        defaults.set(groqModel, forKey: Key.groqModel)
        defaults.set(readsDifficultPages, forKey: Key.readsDifficultPages)
        defaults.set(shortensTitles, forKey: Key.shortensTitles)
        defaults.set(suggestsCategories, forKey: Key.suggestsCategories)
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
        static let intelligenceProvider = "settings.intelligenceProvider"
        static let claudeModel = "settings.claudeModel"
        static let groqModel = "settings.groqModel"
        static let readsDifficultPages = "settings.readsDifficultPages"
        static let shortensTitles = "settings.shortensTitles"
        static let suggestsCategories = "settings.suggestsCategories"
    }
}
