import Foundation

/// Whether a quota window is being spent faster than time passes. Derived only from one snapshot:
/// used %, the window length and the reset time. No history needed.
public struct UsagePace: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Window just started: a projection would be noise.
        case tooEarly
        case comfortable
        /// At the current rate the quota runs out before the window resets.
        case fast
        case depleted
    }

    public let status: Status
    /// Where a perfectly even spender would be right now (elapsed share of the window, 0...100).
    public let expectedUsedPercent: Double
    /// Used % at reset if the current rate holds. May exceed 100. Nil when too early or depleted.
    public let projectedUsedAtReset: Double?
    /// When the quota is projected to hit 100 %, only set for `.fast`.
    public let exhaustsAt: Date?

    /// Below this share of the window (or under 5 minutes) there is not enough signal to project.
    static let minimumElapsedFraction = 0.05
    /// Projections up to 5 % over 100 still count as comfortable, to avoid flicker around the line.
    static let fastThreshold = 105.0

    /// Nil when the window has no duration, no reset, or its reset already passed (outdated reading).
    public init?(window: UsageWindow, now: Date = Date()) {
        guard let minutes = window.windowMinutes, minutes > 0,
              let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let total = TimeInterval(minutes) * 60
        let remaining = min(total, max(0, resetsAt.timeIntervalSince(now)))
        let elapsed = total - remaining
        let fraction = elapsed / total
        let used = window.displayUsedPercent

        expectedUsedPercent = fraction * 100

        if used >= 100 {
            status = .depleted
            projectedUsedAtReset = nil
            exhaustsAt = nil
        } else if fraction < Self.minimumElapsedFraction || elapsed < 5 * 60 {
            status = .tooEarly
            projectedUsedAtReset = nil
            exhaustsAt = nil
        } else {
            let projected = used / fraction
            projectedUsedAtReset = projected
            if projected > Self.fastThreshold {
                status = .fast
                let secondsPerPercent = elapsed / used
                exhaustsAt = now.addingTimeInterval((100 - used) * secondsPerPercent)
            } else {
                status = .comfortable
                exhaustsAt = nil
            }
        }
    }
}
