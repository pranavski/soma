import Foundation
import Security
import Auth

// Backs Supabase's session storage with the iOS Keychain.
// Items are bound to this device only (no iCloud sync) and unlocked
// after first unlock so cold launches don't force re-auth.

struct KeychainAuthStorage: AuthLocalStorage {
    private static let service = "com.soma.supabase.auth"

    func store(key: String, value: Data) throws {
        // Replace any existing value atomically.
        let base = Self.baseQuery(key: key)
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func retrieve(key: String) throws -> Data? {
        var query = Self.baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(Self.baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Keychain error \(status)"
    }
}
