#if os(iOS)
import ActivityKit
import Foundation

public struct UsageActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum PaceStatus: String, Codable, Hashable, Sendable {
            case tooEarly, comfortable, fast, depleted
        }

        public var sessionUsedPercent: Double
        public var weeklyUsedPercent: Double?
        public var sessionResetsAt: Date
        public var sessionWindowMinutes: Int
        public var paceStatus: PaceStatus
        public var exhaustsAt: Date?
        public var expectedUsedPercent: Double?
        public var displayMode: DisplayMode
        public var lastUpdated: Date
        public var lastChangedAt: Date
        public var manuallyStarted: Bool

        public init(sessionUsedPercent: Double, weeklyUsedPercent: Double?, sessionResetsAt: Date,
                    sessionWindowMinutes: Int, paceStatus: PaceStatus, exhaustsAt: Date?,
                    expectedUsedPercent: Double?, displayMode: DisplayMode,
                    lastUpdated: Date, lastChangedAt: Date, manuallyStarted: Bool) {
            self.sessionUsedPercent = sessionUsedPercent
            self.weeklyUsedPercent = weeklyUsedPercent
            self.sessionResetsAt = sessionResetsAt
            self.sessionWindowMinutes = sessionWindowMinutes
            self.paceStatus = paceStatus
            self.exhaustsAt = exhaustsAt
            self.expectedUsedPercent = expectedUsedPercent
            self.displayMode = displayMode
            self.lastUpdated = lastUpdated
            self.lastChangedAt = lastChangedAt
            self.manuallyStarted = manuallyStarted
        }

        public var sessionWindow: UsageWindow {
            UsageWindow(kind: .session, usedPercent: sessionUsedPercent,
                        windowMinutes: sessionWindowMinutes, resetsAt: sessionResetsAt)
        }
        public var weeklyWindow: UsageWindow? {
            weeklyUsedPercent.map { UsageWindow(kind: .weekly, usedPercent: $0,
                                                 windowMinutes: nil, resetsAt: nil) }
        }
    }

    public var providerID: String
    public var providerName: String

    public init(providerID: String, providerName: String) {
        self.providerID = providerID
        self.providerName = providerName
    }
}

public extension UsageActivityAttributes.ContentState.PaceStatus {
    init(_ status: UsagePace.Status?) {
        switch status {
        case .tooEarly, nil: self = .tooEarly
        case .comfortable: self = .comfortable
        case .fast: self = .fast
        case .depleted: self = .depleted
        }
    }
}
#endif
