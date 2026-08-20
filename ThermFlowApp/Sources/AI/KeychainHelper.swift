import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.coolcumber.api-key"

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    func save(key: String, account: String) -> Bool {
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return false }

        var item = query(account: account)
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            // Remove plaintext values created by older builds after a successful migration.
            UserDefaults.standard.removeObject(forKey: "api_key_\(account)")
            return true
        }
        return false
    }
    
    func read(account: String) -> String? {
        var item = query(account: account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        // One-time migration from the plaintext storage used by pre-security builds.
        let legacyKey = "api_key_\(account)"
        if let legacyValue = UserDefaults.standard.string(forKey: legacyKey),
           save(key: legacyValue, account: account) {
            return legacyValue
        }
        return nil
    }
    
    func delete(account: String) {
        let item = query(account: account)
        SecItemDelete(item as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "api_key_\(account)")
    }
}
