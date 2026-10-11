import Foundation

/// Patterns read from recorded used-% history: how often the session limit was hit this week and which hours of
/// the day usage tends to grow. Pure; the history comes from the phone and, when connected, the Mac relay.
public struct UsageInsights: Sendable, Equatable {
    /// Session windows that reached 100 % since the current weekly window started (or in the last 7 days).
    public let sessionExhaustions: Int
    /// Whether any session reading falls in that period at all; without it the count means nothing.
    public let hasSessionHistory: Bool
    /// Earliest reading considered, to say how far back the patterns reach.
    public let coverageStart: Date?
    /// Used-% growth per local hour of day (index 0...23), summed over the last 7 days.
    public let hourlyIncrease: [Double]

    static let lookback: TimeInterval = 7 * 86400
    /// Growth across a longer gap between readings cannot be placed in time, so it is left out.
    static let maximumGap: TimeInterval = 6 * 3600
    /// Readings belong to the same window instance when their resets are this close.
    static let resetTolerance: TimeInterval = 120

    public init(providerID: String, history: [HistorySeries], weekly: UsageWindow? = nil,
                now: Date = Date(), calendar: Calendar = .current) {
        let lookbackStart = now.addingTimeInterval(-Self.lookback)
        var weekStart = lookbackStart
        if let weekly, let minutes = weekly.windowMinutes, let reset = weekly.resetsAt, reset > now {
            weekStart = max(lookbackStart, reset.addingTimeInterval(-TimeInterval(minutes) * 60))
        }

        func points(_ kind: UsageWindow.Kind) -> [HistoryPoint] {
            history.filter { $0.providerID == providerID && $0.kind == kind }
                .flatMap(\.points)
                .filter { $0.used.isFinite && $0.t <= now }
                .sorted { $0.t < $1.t }
        }

        // Exhaustions: distinct session instances (grouped by reset time) with a reading at or above 100 %.
        let session = points(.session).filter { $0.t >= weekStart }
        hasSessionHistory = !session.isEmpty
        var exhaustedResets: [Date] = []
        for point in session where point.used >= 100 {
            let reset = point.resetsAt ?? point.t
            if !exhaustedResets.contains(where: { abs($0.timeIntervalSince(reset)) <= Self.resetTolerance }) {
                exhaustedResets.append(reset)
            }
        }
        sessionExhaustions = exhaustedResets.count

        // Peak hours from the weekly lane, which keeps growing across session resets; fall back to sessions.
        var lane = points(.weekly).filter { $0.t >= lookbackStart }
        if lane.count < 2 { lane = points(.session).filter { $0.t >= lookbackStart } }
        var hours = Array(repeating: 0.0, count: 24)
        for (previous, next) in zip(lane, lane.dropFirst()) {
            let gap = next.t.timeIntervalSince(previous.t)
            guard gap > 0, gap <= Self.maximumGap, Self.sameInstance(previous, next) else { continue }
            let growth = min(100, next.used) - max(0, previous.used)
            guard growth > 0 else { continue }
            Self.spread(growth, from: previous.t, to: next.t, into: &hours, calendar: calendar)
        }
        hourlyIncrease = hours
        coverageStart = (lane.first?.t).map { min($0, session.first?.t ?? $0) } ?? session.first?.t
    }

    /// Hours (0...23) with the most growth, busiest first; at most `limit`, only hours that saw any.
    public func peakHours(limit: Int = 3) -> [Int] {
        hourlyIncrease.enumerated()
            .filter { $0.element > 0.05 }
            .sorted { $0.element == $1.element ? $0.offset < $1.offset : $0.element > $1.element }
            .prefix(limit)
            .map(\.offset)
    }

    /// True when there is enough growth recorded to talk about peak hours.
    public var hasHourlyPattern: Bool { hourlyIncrease.reduce(0, +) >= 1 }

    private static func sameInstance(_ a: HistoryPoint, _ b: HistoryPoint) -> Bool {
        guard let ra = a.resetsAt, let rb = b.resetsAt else { return a.resetsAt == nil && b.resetsAt == nil }
        return abs(ra.timeIntervalSince(rb)) <= resetTolerance
    }

    /// Splits `amount` over the clock hours between `start` and `end`, in proportion to time spent in each.
    private static func spread(_ amount: Double, from start: Date, to end: Date,
                               into hours: inout [Double], calendar: Calendar) {
        let total = end.timeIntervalSince(start)
        var cursor = start
        while cursor < end {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let next = min(end, hourStart.addingTimeInterval(3600))
            guard next > cursor else { break }
            let hour = calendar.component(.hour, from: cursor)
            hours[hour] += amount * next.timeIntervalSince(cursor) / total
            cursor = next
        }
    }
}
