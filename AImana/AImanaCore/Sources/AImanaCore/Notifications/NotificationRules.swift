import Foundation

/// Whether this iPhone's own sign-in for a provider still works. Nil (absent) means it could not be determined.
public enum PhoneLoginStatus: Sendable, Equatable {
    case signedOut
    case active
    /// Token refresh or the usage call was rejected: the user has to sign in again.
    case expired
}

/// Whose credentials a "sign-in expired" alert is about: this iPhone's own sign-in, or the CLI sign-in the Mac
/// relay reads (`mac` when the iPhone announces it, `thisMac` when the Mac app itself does).
public enum LoginAlertOrigin: Sendable, Equatable {
    case phone
    case mac
    case thisMac
}

/// What was already announced, persisted between refreshes so nothing is sent twice.
public struct NotificationState: Codable, Equatable, Sendable {
    /// Keyed like `NotificationPreferences.key(providerID:lane:)`.
    public var windows: [String: WindowAlertState]
    /// Providers whose expired sign-in was announced; cleared once the sign-in works again or is removed.
    public var loginNotified: Set<String>

    public init(windows: [String: WindowAlertState] = [:], loginNotified: Set<String> = []) {
        self.windows = windows
        self.loginNotified = loginNotified
    }
}

/// Last accepted reading of one lane, plus what was announced for the current window instance.
public struct WindowAlertState: Codable, Equatable, Sendable {
    public var providerID: String
    public var providerName: String
    public var lane: AlertLane
    /// Identifies the window instance. Providers can jitter it by seconds between calls.
    public var resetsAt: Date?
    public var lastUsedPercent: Double
    public var peakUsedPercent: Double
    /// `UsageInfo.lastUpdated` of the accepted reading; older or replayed readings are ignored.
    public var lastUpdated: Date
    public var firedThresholds: Set<Int>
    public var paceNotified: Bool

    public init(providerID: String, providerName: String, lane: AlertLane, resetsAt: Date?,
                lastUsedPercent: Double, peakUsedPercent: Double, lastUpdated: Date,
                firedThresholds: Set<Int> = [], paceNotified: Bool = false) {
        self.providerID = providerID
        self.providerName = providerName
        self.lane = lane
        self.resetsAt = resetsAt
        self.lastUsedPercent = lastUsedPercent
        self.peakUsedPercent = peakUsedPercent
        self.lastUpdated = lastUpdated
        self.firedThresholds = firedThresholds
        self.paceNotified = paceNotified
    }
}

/// Small pure rules the planner combines. Kept separate so each one is easy to test and reason about.
public enum NotificationRules {
    /// Reset times closer than this are the same window instance (Codex derives them from "seconds left").
    static let resetTolerance: TimeInterval = 10 * 60
    /// Without reset times, a drop this large in used % can only be a reset.
    static let resetDropPercent = 25.0

    /// True when `window` belongs to a later window instance than the one `previous` tracked.
    public static func isNewInstance(previous: WindowAlertState, window: UsageWindow, now: Date) -> Bool {
        switch (previous.resetsAt, window.resetsAt) {
        case let (old?, new?):
            return new.timeIntervalSince(old) > resetTolerance
        case let (old?, nil):
            // The tracked window already ended and the new one has not started counting yet.
            return now >= old
        case (nil, _):
            return window.displayUsedPercent < previous.lastUsedPercent - resetDropPercent
        }
    }

    /// The window was depleted or spent past the highest threshold, so its reset is good news.
    public static func isArmedForRecovery(_ state: WindowAlertState, settings: WindowAlertSettings) -> Bool {
        state.peakUsedPercent >= 100 || state.peakUsedPercent >= settings.recoveryLevel
    }

    /// Readings with a failed refresh (stale data), past their reset, or older than the last accepted one never alert.
    public static func isUsable(window: UsageWindow, usage: UsageInfo, previous: WindowAlertState?, now: Date) -> Bool {
        guard !window.isOutdated(now: now) else { return false }
        if let previous, usage.lastUpdated <= previous.lastUpdated { return false }
        return true
    }
}
