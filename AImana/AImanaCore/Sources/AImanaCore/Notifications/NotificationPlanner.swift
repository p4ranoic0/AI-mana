import Foundation

/// One local notification the app should hand to iOS. Text is already localized.
public struct PlannedNotification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case threshold(Int)
        case fastPace
        case recovered
        case loginExpired
        case dailySummary
    }

    public enum Trigger: Sendable, Equatable {
        case now
        case at(Date)
        /// Repeats every day at this local time.
        case daily(hour: Int, minute: Int)
    }

    public let id: String
    public let kind: Kind
    public let providerID: String?
    public let lane: AlertLane?
    public let title: String
    public let body: String
    /// Groups a provider's alerts together in Notification Center.
    public let threadID: String
    public let trigger: Trigger
}

public struct NotificationPlan: Sendable, Equatable {
    /// Send right away.
    public var deliver: [PlannedNotification]
    /// Every scheduled request that should be pending afterwards. Pending requests with an id starting with one of
    /// `NotificationPlanner.scheduledPrefixes` but missing here must be removed.
    public var pending: [PlannedNotification]
    /// Persist this for the next run.
    public var state: NotificationState
}

/// Decides which notifications a refresh produces. Pure: no clock, no storage, no UserNotifications.
public enum NotificationPlanner {
    public static let scheduledPrefixes = ["recovered.", "summary."]
    static let summaryID = "summary.daily"
    static let summaryThread = "summary"

    public static func plan(state previous: NotificationState, states: [ProviderState],
                            logins: [String: PhoneLoginStatus], loginOrigin: LoginAlertOrigin = .phone,
                            macLoginProviderIDs: Set<String> = [],
                            preferences: NotificationPreferences,
                            displayMode: DisplayMode = .used, now: Date, locale: Locale? = nil,
                            calendar: Calendar = .current) -> NotificationPlan {
        var state = previous
        var deliver: [PlannedNotification] = []
        let enabled = preferences.isEnabled
        let text = NotificationText(locale: locale, now: now)

        for provider in states where provider.error == nil {
            guard let usage = provider.usage else { continue }
            for lane in AlertLane.allCases {
                guard let window = usage.window(lane.kind) else { continue }
                let key = NotificationPreferences.key(providerID: provider.providerID, lane: lane)
                let old = state.windows[key]
                guard NotificationRules.isUsable(window: window, usage: usage, previous: old, now: now) else { continue }
                let settings = preferences.window(providerID: provider.providerID, lane: lane)
                let used = window.displayUsedPercent

                var current: WindowAlertState
                let baseline: Double
                if let old, !NotificationRules.isNewInstance(previous: old, window: window, now: now) {
                    current = old
                    baseline = old.lastUsedPercent
                    // Follow small jitter so a scheduled reset announcement fires at the latest known time.
                    if let resetsAt = window.resetsAt { current.resetsAt = resetsAt }
                } else {
                    // A reset scheduled for the future (or never scheduled) did not announce itself: say it now.
                    if let old, enabled, preferences.recoveryAlerts,
                       NotificationRules.isArmedForRecovery(old, settings: settings),
                       (old.resetsAt.map { $0 > now } ?? true) {
                        deliver.append(text.recovered(old, key: key, immediateID: true))
                    }
                    current = WindowAlertState(providerID: provider.providerID, providerName: usage.providerName,
                                               lane: lane, resetsAt: window.resetsAt, lastUsedPercent: used,
                                               peakUsedPercent: used, lastUpdated: usage.lastUpdated)
                    // The very first sighting is a silent baseline; after a reset the climb starts from zero.
                    baseline = old == nil ? used : 0
                }
                current.providerName = usage.providerName

                let crossed = SeverityTransitions.crossedThresholds(settings.thresholds, from: baseline, to: used,
                                                                    alreadyFired: current.firedThresholds)
                current.firedThresholds.formUnion(crossed)
                if let top = crossed.last, enabled, settings.isEnabled {
                    deliver.append(text.threshold(top, used: used, window: window, state: current, key: key))
                }

                if enabled, preferences.paceAlerts, !current.paceNotified,
                   let pace = UsagePace(window: window, now: now), pace.status == .fast, let exhausts = pace.exhaustsAt {
                    deliver.append(text.fastPace(exhausts: exhausts, window: window, state: current, key: key))
                    current.paceNotified = true
                }

                current.lastUsedPercent = used
                current.peakUsedPercent = max(current.peakUsedPercent, used)
                current.lastUpdated = usage.lastUpdated
                state.windows[key] = current
            }
        }

        for (providerID, status) in logins.sorted(by: { $0.key < $1.key }) {
            switch status {
            case .expired:
                guard enabled, preferences.loginAlerts, !state.loginNotified.contains(providerID) else { continue }
                let name = states.first { $0.providerID == providerID }?.displayName ?? providerID
                let origin: LoginAlertOrigin = macLoginProviderIDs.contains(providerID) ? .mac : loginOrigin
                deliver.append(text.loginExpired(providerID: providerID, displayName: name, origin: origin))
                state.loginNotified.insert(providerID)
            case .active, .signedOut:
                state.loginNotified.remove(providerID)
            }
        }

        let pending = pending(state: state, usages: states.compactMap(\.usage), preferences: preferences,
                              displayMode: displayMode, now: now, locale: locale, calendar: calendar)
        return NotificationPlan(deliver: deliver, pending: pending, state: state)
    }

    /// Scheduled requests only: reset announcements for armed windows and the daily summary. Used after each
    /// refresh and whenever the settings change.
    public static func pending(state: NotificationState, usages: [UsageInfo], preferences: NotificationPreferences,
                               displayMode: DisplayMode = .used, now: Date, locale: Locale? = nil,
                               calendar: Calendar = .current) -> [PlannedNotification] {
        guard preferences.isEnabled else { return [] }
        let text = NotificationText(locale: locale, now: now)
        var result: [PlannedNotification] = []
        if preferences.recoveryAlerts {
            for (key, window) in state.windows.sorted(by: { $0.key < $1.key }) {
                guard let resetsAt = window.resetsAt, resetsAt > now else { continue }
                let settings = preferences.window(providerID: window.providerID, lane: window.lane)
                guard NotificationRules.isArmedForRecovery(window, settings: settings) else { continue }
                result.append(text.recovered(window, key: key, immediateID: false))
            }
        }
        if preferences.dailySummary {
            let hour = preferences.summaryMinutes / 60, minute = preferences.summaryMinutes % 60
            let nextFire = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute),
                                             matchingPolicy: .nextTime) ?? now
            result.append(text.dailySummary(usages: usages, mode: displayMode, nextFire: nextFire,
                                            hour: hour, minute: minute, id: summaryID, thread: summaryThread))
        }
        return result
    }
}
