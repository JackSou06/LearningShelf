import Foundation
import Security

enum KeyStore {
    static let service = "com.jacksou.LearningShelf.openai"
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "openai"] }
    static func exists() -> Bool { SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess }
    static func load() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CourseFailure(message: "Keychain 未能保存金鑰") }
        } else if update != errSecSuccess { throw CourseFailure(message: "Keychain 未能更新金鑰") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
