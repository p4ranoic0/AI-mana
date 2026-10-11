#if canImport(Security)
import Foundation
import Security

public struct KeychainError: Error, Sendable, Equatable {
    public let status: OSStatus
}

/// Generic-password Keychain wrapper. Secrets never leave the Keychain except through `read`.
///
/// Items are readable after the first unlock so the widget can renew and use them while the phone is locked.
/// With an `accessGroup`, the app and its widget share items through `keychain-access-groups`. The group is the app's
/// own default one (`<TeamID>.<bundle prefix>.aimana`), where items saved without an explicit group already live, so
/// nothing needs migrating; reads still fall back to a group-less lookup in case an item ended up elsewhere, and an
/// unsigned build (no entitlement) falls back to group-less writes.
public struct KeychainService: CredentialStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(_ key: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    /// The explicit group first, then any group this process can see.
    private var lookupGroups: [String?] { accessGroup == nil ? [nil] : [accessGroup, nil] }

    public func read(_ key: String) throws -> String? {
        var firstError: KeychainError?
        for group in lookupGroups {
            var query = baseQuery(key, group: group)
            query[kSecReturnData as String] = true
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess, let found = item as? [String: Any],
                  let data = found[kSecValueData as String] as? Data else {
                firstError = firstError ?? KeychainError(status: status)
                continue
            }
            // Items from an older build may use a stricter class that the locked phone cannot read.
            if (found[kSecAttrAccessible as String] as? String) != (kSecAttrAccessibleAfterFirstUnlock as String) {
                SecItemUpdate(baseQuery(key, group: group) as CFDictionary,
                              [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
            }
            return String(data: data, encoding: .utf8)
        }
        if let firstError { throw firstError }
        return nil
    }

    public func write(_ value: String, for key: String) throws {
        do {
            try write(value, for: key, group: accessGroup)
        } catch let error as KeychainError where accessGroup != nil && error.status == errSecMissingEntitlement {
            try write(value, for: key, group: nil)   // unsigned build without keychain-access-groups
        }
    }

    private func write(_ value: String, for key: String, group: String?) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(baseQuery(key, group: group) as CFDictionary,
                                   [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = baseQuery(key, group: group)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Removes the item from the explicit group and from wherever else a group-less lookup finds it.
    public func delete(_ key: String) throws {
        var failure: KeychainError?
        for group in lookupGroups {
            let status = SecItemDelete(baseQuery(key, group: group) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
                failure = failure ?? KeychainError(status: status)
                continue
            }
        }
        if let failure { throw failure }
    }
}
#endif
