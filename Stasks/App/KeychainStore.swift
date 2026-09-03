import Foundation
import Security
import StasksCore

enum KeychainStore {
    static let service = "com.lucianostegun.stasks"
    static let slackToken = "slack.userToken"
    static let anthropicKey = "anthropic.apiKey"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns the OSStatus of the write, or `errSecSuccess` when clearing an empty value.
    @discardableResult
    static func set(_ key: String, _ value: String) -> OSStatus {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { delete(key); return errSecSuccess }
        delete(key)
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: key, kSecValueData as String: Data(trimmed.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { Log.ui.error("keychain write failed for \(key, privacy: .public): \(status, privacy: .public)") }
        return status
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
