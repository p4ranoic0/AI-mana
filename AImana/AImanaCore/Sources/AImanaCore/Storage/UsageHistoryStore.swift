import Foundation

/// The phone's own used-% history, kept next to the snapshot so burndowns and patterns work without the Mac.
/// Named apart from the relay's `HistoryStore`, which keeps the Mac's copy.
public final class UsageHistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func appGroup(_ identifier: String, fileName: String = "usage-history.json") -> UsageHistoryStore? {
        #if os(Linux)
        nil
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            .map { UsageHistoryStore(fileURL: $0.appendingPathComponent(fileName)) }
        #endif
    }

    public func load() -> [HistorySeries] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // One unreadable series (e.g. a lane kind from a newer build) must not cost the rest.
        return ((try? decoder.decode([Lossy<HistorySeries>].self, from: data)) ?? []).compactMap(\.value)
    }

    public func save(_ series: [HistorySeries]) throws {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(series).write(to: fileURL, options: .atomic)
    }

    /// Adds fresh readings (8-day retention, older than a day thinned to 30-minute buckets) and returns the result.
    @discardableResult
    public func record(_ usages: [UsageInfo], now: Date = Date()) -> [HistorySeries] {
        let updated = HistoryRecorder.downsampled(HistoryRecorder.record(load(), with: usages, now: now), now: now)
        try? save(updated)
        return updated
    }
}
