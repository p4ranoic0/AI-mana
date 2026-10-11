import Foundation

/// How much of a multi-day window can be spent per day from now on to land at exactly 100 % at reset.
/// Computed on the device from one snapshot; "today" figures additionally need recorded history.
public struct DailyBudget: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// More than a day left: `perDayPercent` is the even daily share of what remains.
        case spread
        /// Under a day left: everything remaining can go before the reset.
        case lastDay
        case depleted
        /// The reset already passed; the reading says nothing about the new window.
        case outdated
    }

    public let status: Status
    /// Remaining % divided by days left (days counted with fractions, at least one). 0 when depleted or outdated.
    public let perDayPercent: Double
    /// Days until reset, with fractions. 0 when outdated.
    public let daysLeft: Double
    public let remainingPercent: Double
    public let resetsAt: Date
    /// Used % spent since local midnight, when history covers the start of the day.
    public let usedToday: Double?
    /// The daily allowance as it stood at local midnight, so it does not shrink while you spend it.
    public let todayBudgetPercent: Double?

    /// Only windows of at least two days get a daily budget; a 5-hour session has nothing to spread.
    static let minimumWindowMinutes = 2 * 1440
    /// A baseline reading this long before midnight still describes the start of the day.
    static let baselineTolerance: TimeInterval = 12 * 3600
    /// Readings from the history belong to this window when their reset is within this of the window's.
    static let resetTolerance: TimeInterval = 120

    /// Nil for short windows or windows without a duration or reset.
    public init?(window: UsageWindow, history: [HistorySeries] = [], providerID: String? = nil,
                 now: Date = Date(), calendar: Calendar = .current) {
        guard let minutes = window.windowMinutes, minutes >= Self.minimumWindowMinutes,
              let resetsAt = window.resetsAt else { return nil }
        self.resetsAt = resetsAt
        remainingPercent = window.remainingPercent

        guard resetsAt > now else {
            status = .outdated
            perDayPercent = 0
            daysLeft = 0
            usedToday = nil
            todayBudgetPercent = nil
            return
        }

        let days = resetsAt.timeIntervalSince(now) / 86400
        daysLeft = days
        if window.displayUsedPercent >= 100 {
            status = .depleted
            perDayPercent = 0
        } else {
            status = days < 1 ? .lastDay : .spread
            perDayPercent = window.remainingPercent / max(1, days)
        }

        // "Today": compare with the reading that stood at local midnight (or the window start, if later).
        let windowStart = resetsAt.addingTimeInterval(-TimeInterval(minutes) * 60)
        let dayStart = calendar.startOfDay(for: now)
        let baseline: (time: Date, used: Double)?
        if windowStart >= dayStart {
            baseline = (windowStart, 0)
        } else if let providerID {
            baseline = history
                .filter { $0.providerID == providerID && $0.kind == window.kind }
                .flatMap(\.points)
                .filter { point in
                    guard let reset = point.resetsAt, point.used.isFinite else { return false }
                    return abs(reset.timeIntervalSince(resetsAt)) <= Self.resetTolerance
                        && point.t <= dayStart && point.t >= dayStart.addingTimeInterval(-Self.baselineTolerance)
                }
                .max { $0.t < $1.t }
                .map { ($0.t, min(100, max(0, $0.used))) }
        } else {
            baseline = nil
        }
        if let baseline {
            let start = max(baseline.time, dayStart)
            let daysAtStart = max(1, resetsAt.timeIntervalSince(start) / 86400)
            todayBudgetPercent = (100 - baseline.used) / daysAtStart
            usedToday = max(0, window.displayUsedPercent - baseline.used)
        } else {
            todayBudgetPercent = nil
            usedToday = nil
        }
    }

    /// Share of today's allowance already spent (may exceed 1). Nil without history.
    public var todayFraction: Double? {
        guard let usedToday, let todayBudgetPercent, todayBudgetPercent > 0 else { return nil }
        return usedToday / todayBudgetPercent
    }

    /// Headline: "14% per day", "28% until reset", "Used up", or "Reset passed".
    public func headline(locale: Locale? = nil) -> String {
        switch status {
        case .spread:
            return CoreStrings.format("%@ per day", locale: locale, UsageFormatter.percentText(perDayPercent))
        case .lastDay:
            return CoreStrings.format("%@ until reset", locale: locale, UsageFormatter.percentText(perDayPercent))
        case .depleted:
            return CoreStrings.text("Used up", locale: locale)
        case .outdated:
            return CoreStrings.text("Reset passed", locale: locale)
        }
    }

    /// Explains the headline: "For the next 4d 1h to land at 100%", "Resets in 2d 3h", ...
    public func caption(now: Date = Date(), locale: Locale? = nil) -> String {
        let countdown = UsageFormatter.resetCountdown(to: resetsAt, now: now, locale: locale)
        switch status {
        case .spread:
            return CoreStrings.format("For the next %@ to land at 100%%", locale: locale, countdown)
        case .lastDay, .depleted:
            return CoreStrings.format("Resets in %@", locale: locale, countdown)
        case .outdated:
            return CoreStrings.text("Refresh for the new window", locale: locale)
        }
    }

    /// "Today 6% of 14%", or nil without history.
    public func todayText(locale: Locale? = nil) -> String? {
        guard status == .spread || status == .lastDay,
              let usedToday, let todayBudgetPercent else { return nil }
        return CoreStrings.format("Today %@ of %@", locale: locale,
                                  UsageFormatter.percentText(usedToday), UsageFormatter.percentText(todayBudgetPercent))
    }

    /// One short line for cards: "14%/day · today 6%" or the headline alone.
    public func compactText(locale: Locale? = nil) -> String {
        guard status == .spread else { return headline(locale: locale) }
        let perDay = CoreStrings.format("%@/day", locale: locale, UsageFormatter.percentText(perDayPercent))
        guard let usedToday, todayBudgetPercent != nil else { return perDay }
        return perDay + " · " + CoreStrings.format("today %@", locale: locale, UsageFormatter.percentText(usedToday))
    }
}
