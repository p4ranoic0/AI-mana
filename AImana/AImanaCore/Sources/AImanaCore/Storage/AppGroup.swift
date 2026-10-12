import Foundation

public enum AppGroup {
    private static var bundlePrefix: String {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AImanaBundlePrefix") as? String,
              !prefix.isEmpty, !prefix.contains("$") else { return "com.example" }
        return prefix
    }
    public static var identifier: String { "group.\(bundlePrefix).aimana" }
    public static var keychainService: String { "\(bundlePrefix).aimana" }
    public static var sharedContainerAvailable: Bool {
        #if !canImport(Darwin)
        false
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
        #endif
    }

    /// Snapshot file shared with the widget. Falls back to Application Support when the App Group
    /// entitlement is unavailable (e.g. unsigned simulator builds), so the app still works in Xcode.
    public static func snapshotStore() -> SnapshotStore {
        if let store = SnapshotStore.appGroup(identifier) { return store }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SnapshotStore(fileURL: dir.appendingPathComponent("usage-snapshot.json"))
    }

    /// The phone's own used-% history, next to the snapshot (same fallback).
    public static func historyStore() -> UsageHistoryStore {
        if let store = UsageHistoryStore.appGroup(identifier) { return store }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return UsageHistoryStore(fileURL: dir.appendingPathComponent("usage-history.json"))
    }

    /// Info.plist key both targets fill with `$(AppIdentifierPrefix)` (the team ID plus a dot).
    static let identifierPrefixKey = "AppIdentifierPrefix"

    /// `keychain-access-groups` entry shared by the app and the widget: the app's own default group, so items the
    /// app saved before the widget needed them are already in it. `nil` when the prefix is unknown (unsigned builds).
    public static var keychainAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: identifierPrefixKey) as? String,
              prefix.hasSuffix("."), prefix.count > 1, !prefix.contains("$") else { return nil }
        return prefix + keychainService
    }

    #if canImport(Security)
    public static func keychain() -> KeychainService {
        KeychainService(service: keychainService, accessGroup: keychainAccessGroup)
    }
    #endif

    /// A lock file shared by every process in the App Group (same fallback as the snapshot).
    public static func lock(_ name: String, timeout: TimeInterval = 15) -> FileLock {
        #if !canImport(Darwin)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileLock(url: dir.appendingPathComponent("\(name).lock"), timeout: timeout)
    }
}

public enum CredentialKey {}
