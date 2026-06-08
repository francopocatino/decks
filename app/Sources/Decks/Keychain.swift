import Foundation
import Security

enum Keychain {
    private static let service = "com.francopocatino.decks"

    static func set(_ value: String, for key: String) {
        let base = query(for: key)
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var lookup = query(for: key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(for: key) as CFDictionary)
    }

    private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
