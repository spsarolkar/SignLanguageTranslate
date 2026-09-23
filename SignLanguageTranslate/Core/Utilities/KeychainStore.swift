import Foundation
import Security

/// Minimal wrapper around the Keychain for storing secrets (API tokens, access keys).
///
/// Values are stored as generic passwords under `service`, keyed by account name,
/// and are only readable while the device is unlocked.
struct KeychainStore: Sendable {

    let service: String

    init(service: String = "com.signlanguagetranslate.secrets") {
        self.service = service
    }

    /// Store `value` for `key`, replacing any existing value.
    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// The value stored for `key`, or nil if none.
    func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Remove the value stored for `key`. Returns true if removed or already absent.
    @discardableResult
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Move a plaintext value from UserDefaults into the Keychain, then remove it
    /// from UserDefaults. Leaves an existing Keychain value untouched.
    func migrateFromUserDefaults(key: String, defaults: UserDefaults = .standard) {
        guard let legacy = defaults.string(forKey: key) else { return }
        if string(for: key) == nil {
            guard set(legacy, for: key) else { return }
        }
        defaults.removeObject(forKey: key)
    }
}
