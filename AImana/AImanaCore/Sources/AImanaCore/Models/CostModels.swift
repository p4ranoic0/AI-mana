import Foundation

public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }
}

public struct ModelCost: Codable, Sendable, Equatable, Identifiable {
    public let model: String
    public let tokens: TokenUsage
    /// Nil when the model has no known price (tokens are still counted).
    public let usd: Double?
    public var id: String { model }

    public init(model: String, tokens: TokenUsage, usd: Double?) {
        self.model = model
        self.tokens = tokens
        self.usd = usd
    }
}

/// One local calendar day of usage. `usd` is an API-equivalent estimate from the provider's price list,
/// not what a subscription actually bills.
public struct DailyCost: Codable, Sendable, Equatable, Identifiable {
    /// "yyyy-MM-dd" in the Mac's local time zone.
    public let day: String
    public let tokens: TokenUsage
    public let usd: Double
    /// Tokens whose model had no price; they are excluded from `usd`.
    public let unpricedTokens: Int
    public let models: [ModelCost]
    public var id: String { day }

    public init(day: String, tokens: TokenUsage, usd: Double, unpricedTokens: Int, models: [ModelCost]) {
        self.day = day
        self.tokens = tokens
        self.usd = usd
        self.unpricedTokens = unpricedTokens
        self.models = models
    }
}

public struct CostTotal: Sendable, Equatable {
    public let usd: Double
    public let tokens: TokenUsage
    public let unpricedTokens: Int
}

public struct CostReport: Codable, Sendable, Equatable {
    public let providerID: String
    public let generatedAt: Date
    /// Ascending by day.
    public let days: [DailyCost]

    public init(providerID: String, generatedAt: Date, days: [DailyCost]) {
        self.providerID = providerID
        self.generatedAt = generatedAt
        self.days = days
    }

    /// Sum of the `lastDays` calendar days ending on (and including) `endDay` ("yyyy-MM-dd").
    public func total(lastDays: Int, endingOn endDay: String) -> CostTotal {
        guard lastDays > 0, let end = Self.date(from: endDay) else {
            return CostTotal(usd: 0, tokens: TokenUsage(), unpricedTokens: 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = calendar.date(byAdding: .day, value: -(lastDays - 1), to: end) ?? end
        let start = Self.string(from: startDate)
        let inRange = days.filter { $0.day >= start && $0.day <= endDay }
        return CostTotal(usd: inRange.reduce(0) { $0 + $1.usd },
                         tokens: inRange.reduce(TokenUsage()) { $0 + $1.tokens },
                         unpricedTokens: inRange.reduce(0) { $0 + $1.unpricedTokens })
    }

    static func date(from day: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    static func string(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// One recorded reading of a window's used %. `resetsAt` identifies which window instance it belongs to,
/// so a chart can draw the current window's burndown separately from earlier ones.
public struct HistoryPoint: Codable, Sendable, Equatable {
    public let t: Date
    public let used: Double
    public let resetsAt: Date?

    public init(t: Date, used: Double, resetsAt: Date?) {
        self.t = t
        self.used = used
        self.resetsAt = resetsAt
    }
}

public struct HistorySeries: Codable, Sendable, Equatable {
    public let providerID: String
    public let kind: UsageWindow.Kind
    /// Ascending by time.
    public let points: [HistoryPoint]

    public init(providerID: String, kind: UsageWindow.Kind, points: [HistoryPoint]) {
        self.providerID = providerID
        self.kind = kind
        self.points = points
    }
}
