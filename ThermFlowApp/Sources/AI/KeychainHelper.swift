import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.coolcumber.api-key"
    
    func save(key: String, account: String) -> Bool {
        // Fallback to UserDefaults to avoid keychain prompts on every ad-hoc build
        UserDefaults.standard.set(key, forKey: "api_key_\(account)")
        return true
    }
    
    func read(account: String) -> String? {
        return UserDefaults.standard.string(forKey: "api_key_\(account)")
    }
    
    func delete(account: String) {
        UserDefaults.standard.removeObject(forKey: "api_key_\(account)")
    }
}
