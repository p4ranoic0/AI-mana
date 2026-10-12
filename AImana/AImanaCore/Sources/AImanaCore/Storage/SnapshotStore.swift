import Foundation

/// Persists the last known `UsageInfo` list as JSON. In the app this file lives in the
/// App Group container so the widget can read it without credentials or network.
public final class SnapshotStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func appGroup(_ identifier: String, fileName: String = "usage-snapshot.json") -> SnapshotStore? {
        #if !canImport(Darwin)
        nil
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map { SnapshotStore(fileURL: $0.appendingPathComponent(fileName)) }
        #endif
    }

    public func load() -> [UsageInfo] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageInfo].self, from: data)) ?? []
    }

    public func save(_ items: [UsageInfo]) throws {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: fileURL, options: .atomic)
    }
}
