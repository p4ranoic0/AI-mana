import Foundation

/// A single decision per provider, independent of ActivityKit and the refresh source.
public enum LiveActivityAction: Equatable, Sendable {
    case start, update, end, none
}

public enum LiveActivityPolicy {
    public static let idleLimit: TimeInterval = 2 * 60 * 60

    public static func action(previous: UsageInfo?, current: UsageInfo?,
                              hasActivity: Bool, autoStartEnabled: Bool,
                              manuallyStarted: Bool = false, lastChangedAt: Date?,
                              now: Date = Date()) -> LiveActivityAction {
        guard let current, let session = current.window(.session),
              let reset = session.resetsAt, reset > now else {
            return hasActivity ? .end : .none
        }
        if hasActivity {
            if !autoStartEnabled && !manuallyStarted { return .end }
            let changed = increased(previous: previous, current: current)
            if !changed, let lastChangedAt, now.timeIntervalSince(lastChangedAt) >= idleLimit {
                return .end
            }
            return .update
        }
        guard autoStartEnabled, increased(previous: previous, current: current) else { return .none }
        return .start
    }

    public static func increased(previous: UsageInfo?, current: UsageInfo) -> Bool {
        guard let old = previous?.window(.session), let new = current.window(.session),
              let oldReset = old.resetsAt, let newReset = new.resetsAt,
              abs(oldReset.timeIntervalSince(newReset)) <= 120 else { return false }
        return new.displayUsedPercent > old.displayUsedPercent
    }
}

/// Shared preference for automatic starts. Manual starts remain available when disabled.
public enum LiveActivityPreferences {
    public static let key = "liveActivity.autoStart"
    public static func isEnabled(defaults: UserDefaults = DisplayPreferences.shared) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }
    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = DisplayPreferences.shared) {
        defaults.set(enabled, forKey: key)
    }
}
