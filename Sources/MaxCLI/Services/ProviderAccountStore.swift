import Foundation
import Security

/// Stores multiple named API keys per provider in the macOS Keychain, so
/// sessions on the same provider can run under different accounts
/// (opencode itself only keeps one key per provider in auth.json).
enum ProviderAccountStore {
    private static let service = "dev.maxcli.app.provider-account"

    // MARK: - Keys

    static func key(provider: String, account: String) -> String? {
        var query = baseQuery(provider: provider, account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(provider: String, account: String, key: String) -> Bool {
        let data = key.data(using: .utf8) ?? Data()
        let accountKey = compositeAccount(provider: provider, account: account)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery(provider: provider, account: account) as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(provider: String, account: String) -> Bool {
        SecItemDelete(baseQuery(provider: provider, account: account) as CFDictionary) == errSecSuccess
    }

    // MARK: - Account names

    static func accountNames(provider: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let list = items as? [[String: Any]] else { return [] }
        let prefix = "\(provider)/"
        return list
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .sorted()
    }

    // MARK: - Internals

    private static func compositeAccount(provider: String, account: String) -> String {
        "\(provider)/\(account)"
    }

    private static func baseQuery(provider: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compositeAccount(provider: provider, account: account),
        ]
    }
}
