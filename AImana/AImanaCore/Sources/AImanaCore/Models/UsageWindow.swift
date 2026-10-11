import Foundation

/// One quota lane reported by a provider (e.g. the 5-hour session or the weekly cap).
public struct UsageWindow: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        case session
        case weekly
        /// Weekly lane scoped to one model (e.g. "Sonnet", "Opus").
        case model(String)
        /// Short (session-length) lane scoped to one model, e.g. Codex's "GPT-5.3-Codex-Spark" 5-hour limit.
        case modelSession(String)
        /// Share of a prepaid spending cap already used (e.g. an OpenRouter key's credit limit), not a rate limit.
        case spendLimit
        /// Daily allowance of requests to free models (OpenRouter), reset at midnight UTC.
        case freeRequests
        /// Account-wide allowance over a billing period about a month long.
        case monthly

        /// Stable wire format shared by the snapshot file and the Mac relay: "session", "weekly", "model:<name>", ...
        /// Builds that predate a kind skip lanes of that kind (see `UsageInfo`), so new kinds are safe to add.
        public var wireValue: String {
            switch self {
            case .session: "session"
            case .weekly: "weekly"
            case .model(let name): "model:\(name)"
            case .modelSession(let name): "model-session:\(name)"
            case .spendLimit: "spend-limit"
            case .freeRequests: "free-requests"
            case .monthly: "monthly"
            }
        }

        public init?(wireValue: String) {
            switch wireValue {
            case "session": self = .session
            case "weekly": self = .weekly
            case "spend-limit": self = .spendLimit
            case "free-requests": self = .freeRequests
            case "monthly": self = .monthly
            default:
                if wireValue.hasPrefix("model-session:"), wireValue.count > 14 {
                    self = .modelSession(String(wireValue.dropFirst(14)))
                    return
                }
                guard wireValue.hasPrefix("model:"), wireValue.count > 6 else { return nil }
                self = .model(String(wireValue.dropFirst(6)))
            }
        }

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let kind = Kind(wireValue: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unknown window kind \(raw)"))
            }
            self = kind
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(wireValue)
        }
    }

    public let kind: Kind
    /// Raw provider value; may exceed 100 when over quota. Kept for diagnostics.
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(kind: Kind, usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    /// Used percent clamped for presentation. Non-finite input is treated as 0.
    public var displayUsedPercent: Double {
        guard usedPercent.isFinite else { return 0 }
        return min(100, max(0, usedPercent))
    }

    /// Always within 0...100, even for negative or over-quota input.
    public var remainingPercent: Double { 100 - displayUsedPercent }

    /// A reset in the past only means the reading is outdated, not that quota is back to zero.
    public func isOutdated(now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }
}
