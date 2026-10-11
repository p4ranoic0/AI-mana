import AImanaCore
import Foundation

/// Reads the relay file the user picked once in Settings (kept as a security-scoped bookmark),
/// so it keeps working across launches and background refreshes without any credentials on the phone.
struct BookmarkRelaySource: RelayDataSource {
    private static let bookmarkKey = "relay.fileBookmark"
    private static let nameKey = "relay.fileName"

    static var connectedFileName: String? { UserDefaults.standard.string(forKey: nameKey) }

    static func connect(to url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw UsageProviderError.relayUnavailable }
        defer { url.stopAccessingSecurityScopedResource() }
        UserDefaults.standard.set(try url.bookmarkData(), forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
    }

    static func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    func readData() async throws -> Data {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            throw UsageProviderError.relayUnavailable
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            throw UsageProviderError.relayUnavailable
        }
        guard url.startAccessingSecurityScopedResource() else { throw UsageProviderError.relayUnavailable }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return try await CoordinatedFileSource(url: url).readData()
    }
}
