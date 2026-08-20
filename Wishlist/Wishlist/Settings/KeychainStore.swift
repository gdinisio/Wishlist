//
//  KeychainStore.swift
//  Wishlist
//
//  API keys are credentials, so they live in the Keychain rather than in
//  preferences: encrypted at rest, excluded from backups' plaintext, and
//  readable after first unlock so a background price refresh still works.
//

import Foundation
import Security
import OSLog

nonisolated struct KeychainStore: Sendable {
    private let service: String
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "keychain")

    init(service: String = "com.gdinisio.Wishlist.credentials") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                log.error("Keychain read failed with status \(status, privacy: .public)")
            }
            return nil
        }
        let value = String(data: data, encoding: .utf8)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Stores a value, or removes it when the value is empty. Writing an empty
    /// string is how the user clears a key, and an empty key must not linger.
    func set(_ value: String?, forKey key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            removeValue(forKey: key)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(key: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                log.error("Keychain insert failed with status \(addStatus, privacy: .public)")
            }
        } else if updateStatus != errSecSuccess {
            log.error("Keychain update failed with status \(updateStatus, privacy: .public)")
        }
    }

    func removeValue(forKey key: String) {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain delete failed with status \(status, privacy: .public)")
        }
    }

    func removeAll(keys: [String]) {
        for key in keys { removeValue(forKey: key) }
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

/// Keys under which credentials are stored. Centralised so nothing depends on
/// a string literal repeated across the app.
nonisolated enum CredentialKey {
    static let amazonAccessKey = "amazon.accessKey"
    static let amazonSecretKey = "amazon.secretKey"
    static let amazonPartnerTag = "amazon.partnerTag"
    static let rainforestKey = "rainforest.apiKey"
    static let microlinkKey = "microlink.apiKey"

    static let all = [amazonAccessKey, amazonSecretKey, amazonPartnerTag, rainforestKey, microlinkKey]
}
