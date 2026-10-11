import Foundation

/// Hands back what the last refresh saved for one provider. The widget cannot read the Mac relay (its file is
/// reached through the app's security-scoped bookmark), so it uses this as the relay side of a `HybridProvider`:
/// a direct reading keeps the snapshot's costs and history, and a provider without a phone sign-in keeps its entry.
public struct SnapshotProvider: UsageProvider {
    public let id: String
    public let displayName: String
    private let items: [UsageInfo]

    /// `items` is read once, before the refresh overwrites the file.
    public init(id: String, displayName: String, items: [UsageInfo]) {
        self.id = id
        self.displayName = displayName
        self.items = items
    }

    public func fetchUsage() async throws -> UsageInfo {
        guard let saved = items.first(where: { $0.providerID == id }) else { throw UsageProviderError.relayUnavailable }
        return saved
    }
}
