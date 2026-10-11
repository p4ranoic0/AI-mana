import Foundation

/// Provider-agnostic usage snapshot. The UI only ever sees this type.
public struct UsageInfo: Codable, Sendable, Equatable, Identifiable {
    public let providerID: String
    public let providerName: String
    /// Lanes the provider actually reported. A missing lane is absent, never a synthetic 0%.
    public let windows: [UsageWindow]
    public let plan: String?
    public let lastUpdated: Date
    /// Credits and other balances; empty when the provider reports none. Older snapshots lack this key.
    public let details: [UsageDetail]
    /// Local API-equivalent cost estimate, when the Mac relay publishes one.
    public let cost: CostReport?
    /// Recorded used-% readings, newest last. Empty when the relay has no history yet.
    public let history: [HistorySeries]
    /// Where the Mac got this reading, when it came through the relay and the Mac said. Nil for phone readings,
    /// older relays and source values this build does not know.
    public let source: RelaySource?

    public var id: String { providerID }

    private enum CodingKeys: String, CodingKey {
        case providerID, providerName, windows, plan, lastUpdated, details, cost, history, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try c.decode(String.self, forKey: .providerID)
        providerName = try c.decode(String.self, forKey: .providerName)
        // A lane kind this build does not know (written by a newer relay) is skipped, not fatal.
        windows = try c.decode([Lossy<UsageWindow>].self, forKey: .windows).compactMap(\.value)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        // Same for a balance kind this build does not know.
        details = (try c.decodeIfPresent([Lossy<UsageDetail>].self, forKey: .details) ?? []).compactMap(\.value)
        cost = try c.decodeIfPresent(CostReport.self, forKey: .cost)
        history = try c.decodeIfPresent([HistorySeries].self, forKey: .history) ?? []
        source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap { $0 }.flatMap(RelaySource.init(rawValue:))
    }

    public init(providerID: String, providerName: String, windows: [UsageWindow],
                plan: String?, lastUpdated: Date, details: [UsageDetail] = [],
                cost: CostReport? = nil, history: [HistorySeries] = [], source: RelaySource? = nil) {
        self.providerID = providerID
        self.providerName = providerName
        self.windows = windows
        self.plan = plan
        self.lastUpdated = lastUpdated
        self.details = details
        self.cost = cost
        self.history = history
        self.source = source
    }

    /// Headline lane, chosen by meaning rather than position: session, else weekly, else first reported.
    public var primary: UsageWindow? {
        window(.session) ?? window(.weekly) ?? windows.first
    }

    public func window(_ kind: UsageWindow.Kind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    /// Same snapshot with the relay's cost report and history attached.
    public func withExtras(cost: CostReport?, history: [HistorySeries]) -> UsageInfo {
        UsageInfo(providerID: providerID, providerName: providerName, windows: windows, plan: plan,
                  lastUpdated: lastUpdated, details: details, cost: cost, history: history, source: source)
    }

    /// Same snapshot, tagged with where the Mac got it.
    public func withSource(_ source: RelaySource?) -> UsageInfo {
        UsageInfo(providerID: providerID, providerName: providerName, windows: windows, plan: plan,
                  lastUpdated: lastUpdated, details: details, cost: cost, history: history, source: source)
    }
}
