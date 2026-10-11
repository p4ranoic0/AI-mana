import AImanaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every location the relay reads or writes. Tests and debug runs point these at temporary directories.
public struct RelayPaths: Sendable, Equatable {
    public var home: URL
    /// Relay-owned state: `history.json` and the publish lock.
    public var stateDirectory: URL
    /// Re-creatable caches: prices, the cost scan cache.
    public var caches: URL
    /// Written by the statusline wrapper, read by the relay.
    public var claudeStatuslineFile: URL
    /// Where the statusline wrapper script and its install record live.
    public var supportDirectory: URL
    public var environment: [String: String]

    public init(home: URL, stateDirectory: URL? = nil, caches: URL? = nil, supportDirectory: URL? = nil,
                environment: [String: String] = [:]) {
        self.home = home
        #if os(Linux)
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share", isDirectory: true)
        let cacheHome = environment["XDG_CACHE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".cache", isDirectory: true)
        let support = supportDirectory ?? dataHome.appendingPathComponent("aimana", isDirectory: true)
        self.caches = caches ?? cacheHome.appendingPathComponent("aimana", isDirectory: true)
        #else
        let support = supportDirectory ?? home.appendingPathComponent("Library/Application Support/AImana", isDirectory: true)
        self.caches = caches ?? home.appendingPathComponent("Library/Caches/AImana", isDirectory: true)
        #endif
        self.supportDirectory = support
        self.stateDirectory = stateDirectory ?? support
        self.claudeStatuslineFile = support.appendingPathComponent(ClaudeStatuslineSource.fileName)
        self.environment = environment
    }

    public static var standard: RelayPaths {
        RelayPaths(home: FileManager.default.homeDirectoryForCurrentUser,
                   environment: ProcessInfo.processInfo.environment)
    }

    /// iCloud Drive › AImana › usage-relay.json — the file the iPhone reads.
    public static var defaultOutput: URL {
        #if os(Linux)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AImana")
            .appendingPathComponent(RelayEnvelope.fileName)
        #else
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/AImana")
            .appendingPathComponent(RelayEnvelope.fileName)
        #endif
    }

    public var historyFile: URL { stateDirectory.appendingPathComponent("history.json") }
    public var lockFile: URL { stateDirectory.appendingPathComponent("relay.lock") }

    public var claudeProjectRoots: [URL] {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return custom.split(separator: ",").map { URL(fileURLWithPath: String($0)).appendingPathComponent("projects") }
        }
        return [home.appendingPathComponent(".claude/projects")]
    }

    public var codexSessionRoots: [URL] {
        let base = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return [base.appendingPathComponent("sessions")]
    }

    public static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

/// Recorded used-% readings, persisted between runs. The relay is its only writer (under the publish lock).
public enum HistoryStore {
    public static func load(from url: URL) -> [HistorySeries] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistorySeries].self, from: data)) ?? []
    }

    public static func save(_ series: [HistorySeries], to url: URL) {
        RelayPaths.ensure(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(series) { try? data.write(to: url, options: .atomic) }
    }
}

/// models.dev prices, refreshed at most once a day; a stale copy is used if the network is down.
public enum PricingStore {
    private struct Cached: Codable {
        let fetchedAt: Date
        let table: PricingTable
    }

    private static let ttl: TimeInterval = 24 * 3600

    public static func load(caches: URL, now: Date = Date(), allowDownload: Bool = true) async -> PricingTable {
        let url = caches.appendingPathComponent("pricing.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cached = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Cached.self, from: $0) }
        if let cached, now.timeIntervalSince(cached.fetchedAt) < ttl { return cached.table }

        if allowDownload, let fresh = await download() {
            RelayPaths.ensure(caches)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(Cached(fetchedAt: now, table: fresh)) { try? data.write(to: url, options: .atomic) }
            return fresh
        }
        return cached?.table ?? PricingTable(prices: [:])
    }

    private static func download() async -> PricingTable? {
        var request = URLRequest(url: URL(string: "https://models.dev/api.json")!)
        request.setValue("AImana/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return PricingTable.fromModelsDev(data)
    }
}
