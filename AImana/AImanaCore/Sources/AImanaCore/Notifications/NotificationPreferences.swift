import Foundation

/// The two quota lanes that can raise alerts. Per-model lanes stay silent: they mirror the weekly cap.
public enum AlertLane: String, Codable, CaseIterable, Sendable, Identifiable {
    case session
    case weekly

    public var id: String { rawValue }
    public var kind: UsageWindow.Kind { self == .session ? .session : .weekly }
    public var title: String { kind.title }
}

/// Threshold alerts for one provider lane. Values are always *used* percent, whatever the display mode.
public struct WindowAlertSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Sorted, unique multiples of `NotificationPreferences.thresholdStep` within `thresholdRange`.
    public var thresholds: [Int]

    public init(isEnabled: Bool = true, thresholds: [Int] = NotificationPreferences.defaultThresholds) {
        self.isEnabled = isEnabled
        self.thresholds = NotificationPreferences.normalized(thresholds)
    }

    /// Used % past which a reset is worth announcing: the highest threshold, or depletion when alerts are off.
    public var recoveryLevel: Double {
        guard isEnabled, let top = thresholds.max() else { return 100 }
        return Double(top)
    }
}

/// Everything the user can switch on in Settings › Notifications. Off until the user opts in.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    public static let thresholdRange = 5...100
    public static let thresholdStep = 5
    public static let maxThresholds = 5
    public static let defaultThresholds = [80, 95]
    /// 20:00 local time.
    public static let defaultSummaryMinutes = 20 * 60

    public var isEnabled: Bool
    /// Keyed by `"<providerID>.<lane>"`. A missing entry means the defaults (on, 80 % and 95 %).
    public var windowAlerts: [String: WindowAlertSettings]
    public var paceAlerts: Bool
    public var recoveryAlerts: Bool
    public var loginAlerts: Bool
    public var dailySummary: Bool
    /// Minutes after local midnight.
    public var summaryMinutes: Int

    public init(isEnabled: Bool = false, windowAlerts: [String: WindowAlertSettings] = [:],
                paceAlerts: Bool = true, recoveryAlerts: Bool = true, loginAlerts: Bool = true,
                dailySummary: Bool = false, summaryMinutes: Int = defaultSummaryMinutes) {
        self.isEnabled = isEnabled
        self.windowAlerts = windowAlerts
        self.paceAlerts = paceAlerts
        self.recoveryAlerts = recoveryAlerts
        self.loginAlerts = loginAlerts
        self.dailySummary = dailySummary
        self.summaryMinutes = min(24 * 60 - 1, max(0, summaryMinutes))
    }

    /// Fields added later fall back to their defaults instead of discarding the saved choices.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationPreferences()
        self.init(
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled,
            windowAlerts: try c.decodeIfPresent([String: WindowAlertSettings].self, forKey: .windowAlerts) ?? [:],
            paceAlerts: try c.decodeIfPresent(Bool.self, forKey: .paceAlerts) ?? defaults.paceAlerts,
            recoveryAlerts: try c.decodeIfPresent(Bool.self, forKey: .recoveryAlerts) ?? defaults.recoveryAlerts,
            loginAlerts: try c.decodeIfPresent(Bool.self, forKey: .loginAlerts) ?? defaults.loginAlerts,
            dailySummary: try c.decodeIfPresent(Bool.self, forKey: .dailySummary) ?? defaults.dailySummary,
            summaryMinutes: try c.decodeIfPresent(Int.self, forKey: .summaryMinutes) ?? defaults.summaryMinutes)
    }

    public static func key(providerID: String, lane: AlertLane) -> String { "\(providerID).\(lane.rawValue)" }

    public func window(providerID: String, lane: AlertLane) -> WindowAlertSettings {
        windowAlerts[Self.key(providerID: providerID, lane: lane)] ?? WindowAlertSettings()
    }

    public mutating func setWindow(_ settings: WindowAlertSettings, providerID: String, lane: AlertLane) {
        windowAlerts[Self.key(providerID: providerID, lane: lane)] =
            WindowAlertSettings(isEnabled: settings.isEnabled, thresholds: settings.thresholds)
    }

    /// Clamps to 5...100, snaps to the 5 % grid, drops duplicates and keeps at most `maxThresholds`.
    public static func normalized(_ values: [Int]) -> [Int] {
        let snapped = values.map { value -> Int in
            let rounded = Int((Double(value) / Double(thresholdStep)).rounded()) * thresholdStep
            return min(thresholdRange.upperBound, max(thresholdRange.lowerBound, rounded))
        }
        return Array(Set(snapped).sorted().prefix(maxThresholds))
    }
}

/// App Group storage for the preferences and the dedupe state, next to the other shared preferences.
public enum NotificationStore {
    public static let preferencesKey = "notifications.preferences"
    public static let stateKey = "notifications.state"

    public static func preferences(defaults: UserDefaults = DisplayPreferences.shared) -> NotificationPreferences {
        decode(NotificationPreferences.self, key: preferencesKey, defaults: defaults) ?? NotificationPreferences()
    }

    public static func setPreferences(_ preferences: NotificationPreferences,
                                      defaults: UserDefaults = DisplayPreferences.shared) {
        encode(preferences, key: preferencesKey, defaults: defaults)
    }

    public static func state(defaults: UserDefaults = DisplayPreferences.shared) -> NotificationState {
        decode(NotificationState.self, key: stateKey, defaults: defaults) ?? NotificationState()
    }

    public static func setState(_ state: NotificationState, defaults: UserDefaults = DisplayPreferences.shared) {
        encode(state, key: stateKey, defaults: defaults)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
