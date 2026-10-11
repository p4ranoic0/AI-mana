import Foundation

/// How often usage is fetched while the app is closed (by the widgets and the background task).
public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    public static let standard: RefreshInterval = .oneHour

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) * 60 }

    public var title: String {
        switch self {
        case .fifteenMinutes: CoreStrings.text("refresh.15m")
        case .thirtyMinutes: CoreStrings.text("refresh.30m")
        case .oneHour: CoreStrings.text("refresh.1h")
        case .twoHours: CoreStrings.text("refresh.2h")
        case .fourHours: CoreStrings.text("refresh.4h")
        }
    }
}

/// App Group defaults, so the widget follows the interval chosen in the app.
public enum RefreshPreferences {
    public static let intervalKey = "refresh.interval"
    static let lastAttemptKey = "refresh.lastBackgroundAttempt"

    public static func interval(defaults: UserDefaults = DisplayPreferences.shared) -> RefreshInterval {
        RefreshInterval(rawValue: defaults.integer(forKey: intervalKey)) ?? .standard
    }

    public static func setInterval(_ interval: RefreshInterval, defaults: UserDefaults = DisplayPreferences.shared) {
        defaults.set(interval.rawValue, forKey: intervalKey)
    }

    /// When a widget last started a fetch, successful or not.
    public static func lastAttempt(defaults: UserDefaults = DisplayPreferences.shared) -> Date? {
        defaults.object(forKey: lastAttemptKey) as? Date
    }

    public static func setLastAttempt(_ date: Date, defaults: UserDefaults = DisplayPreferences.shared) {
        defaults.set(date, forKey: lastAttemptKey)
    }
}

/// Whether a widget reload should fetch usage itself. Pure, so the throttling is testable.
public enum RefreshSchedule {
    /// A timeline asks to be reloaded one interval after it was built, a few seconds before the snapshot it just
    /// saved turns that old; without this slack every other reload would skip.
    static let slack: TimeInterval = 120
    /// Several widgets reload together, and a failing fetch would otherwise be retried on every reload.
    public static let minimumGap: TimeInterval = 5 * 60

    /// - Parameters:
    ///   - providerIDs: providers this device can fetch itself (has a phone sign-in for). Nothing to do when empty.
    public static func isDue(snapshot: [UsageInfo], providerIDs: [String], interval: RefreshInterval,
                             lastAttempt: Date?, now: Date) -> Bool {
        guard !providerIDs.isEmpty else { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minimumGap, lastAttempt <= now { return false }
        let ages = providerIDs.map { id -> TimeInterval in
            guard let info = snapshot.first(where: { $0.providerID == id }) else { return .infinity }
            return now.timeIntervalSince(info.lastUpdated)
        }
        return (ages.max() ?? .infinity) >= interval.seconds - slack
    }
}
