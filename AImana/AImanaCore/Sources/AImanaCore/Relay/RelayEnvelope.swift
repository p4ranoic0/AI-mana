import Foundation

/// Stable wire code for a provider failure, so the iPhone can show "sign in on the Mac" etc.
public enum RelayErrorCode: String, Codable, Sendable, Equatable {
    case unauthenticated, rateLimited, decoding, network, server, relayUnavailable

    public init(_ error: UsageProviderError) {
        switch error {
        case .unauthenticated: self = .unauthenticated
        case .rateLimited: self = .rateLimited
        case .decoding: self = .decoding
        case .network: self = .network
        case .server: self = .server
        case .relayUnavailable: self = .relayUnavailable
        }
    }

    public var providerError: UsageProviderError {
        switch self {
        case .unauthenticated: .unauthenticated
        case .rateLimited: .rateLimited(until: nil)
        case .decoding: .decoding
        case .network: .network
        case .server: .server(status: 503)
        case .relayUnavailable: .relayUnavailable
        }
    }
}

/// Where the Mac got a provider's quota. Unknown values from newer Macs decode as nil, not as a failure.
public enum RelaySource: String, Codable, Sendable, Equatable {
    /// Claude Code's own statusline data (`rate_limits`), written locally by the statusline wrapper.
    case statusline
    /// The CLI's local session logs (Codex `rate_limits` events).
    case logs
    /// The provider's usage endpoint, called with the CLI's credentials (opt-in on the Mac).
    case endpoint
}

public struct RelayEntry: Codable, Sendable, Equatable {
    public let providerID: String
    public let usage: UsageInfo?
    public let error: RelayErrorCode?
    /// Absent in files written by older relays.
    public let source: RelaySource?

    private enum CodingKeys: String, CodingKey { case providerID, usage, error, source }

    public init(providerID: String, usage: UsageInfo?, error: RelayErrorCode?, source: RelaySource? = nil) {
        self.providerID = providerID
        self.usage = usage
        self.error = error
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try c.decode(String.self, forKey: .providerID)
        usage = try c.decodeIfPresent(UsageInfo.self, forKey: .usage)
        error = try c.decodeIfPresent(RelayErrorCode.self, forKey: .error)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap { $0 }.flatMap(RelaySource.init(rawValue:))
    }
}

/// The file the Mac publishes (iCloud Drive) and the iPhone reads. Contains usage numbers only — never credentials.
public struct RelayEnvelope: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let fileName = "usage-relay.json"

    public let version: Int
    public let generatedAt: Date
    public let entries: [RelayEntry]
    /// Per-provider local cost reports. Absent in files written by older relays.
    public let costs: [CostReport]
    /// Recorded used-% series for burndown charts. Absent in files written by older relays.
    public let history: [HistorySeries]

    private enum CodingKeys: String, CodingKey { case version, generatedAt, entries, costs, history }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        entries = try c.decode([RelayEntry].self, forKey: .entries)
        costs = try c.decodeIfPresent([CostReport].self, forKey: .costs) ?? []
        history = try c.decodeIfPresent([HistorySeries].self, forKey: .history) ?? []
    }

    public init(version: Int = RelayEnvelope.currentVersion, generatedAt: Date, entries: [RelayEntry],
                costs: [CostReport] = [], history: [HistorySeries] = []) {
        self.version = version
        self.generatedAt = generatedAt
        self.entries = entries
        self.costs = costs
        self.history = history
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Throws `.decoding` for corrupt data or a version this build does not understand.
    public static func decode(_ data: Data) throws -> RelayEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(RelayEnvelope.self, from: data),
              envelope.version == currentVersion else { throw UsageProviderError.decoding }
        return envelope
    }
}
