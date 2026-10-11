import AImanaCore
import ActivityKit
import Foundation

/// Keeps one ActivityKit activity per provider and one compact baseline across app/background launches.
actor LiveActivityService {
    static let shared = LiveActivityService()
    private let baselineKey = "liveActivity.baselines"
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    private struct Baseline: Codable {
        let used: Double
        let resetsAt: Date?
        let lastUpdated: Date

        func usage(providerID: String) -> UsageInfo {
            UsageInfo(providerID: providerID, providerName: providerID,
                      windows: [UsageWindow(kind: .session, usedPercent: used,
                                            windowMinutes: 300, resetsAt: resetsAt)],
                      plan: nil, lastUpdated: lastUpdated)
        }
    }

    func isActive(providerID: String) -> Bool {
        Activity<UsageActivityAttributes>.activities.contains { $0.attributes.providerID == providerID }
    }

    @discardableResult
    func startManually(for usage: UsageInfo) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let session = usage.window(.session), let reset = session.resetsAt,
              reset > Date() else { return false }
        let existing = Activity<UsageActivityAttributes>.activities.filter { $0.attributes.providerID == usage.providerID }
        if let first = existing.first {
            let state = makeState(usage, previous: nil, existing: first.content.state, manual: true)
            await first.update(ActivityContent(state: state, staleDate: usage.lastUpdated.addingTimeInterval(3600)))
            for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            scheduleExpiry(for: usage.providerID, state: state)
            return true
        }
        let state = makeState(usage, previous: nil, existing: nil, manual: true)
        do {
            _ = try Activity.request(attributes: UsageActivityAttributes(providerID: usage.providerID,
                                                                          providerName: usage.providerName),
                                     content: ActivityContent(state: state,
                                                              staleDate: usage.lastUpdated.addingTimeInterval(3600)),
                                     pushType: nil)
            scheduleExpiry(for: usage.providerID, state: state)
            return true
        } catch { return false }
    }

    func end(providerID: String) async {
        expiryTasks.removeValue(forKey: providerID)?.cancel()
        for activity in Activity<UsageActivityAttributes>.activities where activity.attributes.providerID == providerID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func update(with states: [ProviderState]) async {
        let now = Date()
        let defaults = DisplayPreferences.shared
        let previous = (defaults.data(forKey: baselineKey).flatMap { try? JSONDecoder().decode([String: Baseline].self, from: $0) }) ?? [:]
        let current = Dictionary(uniqueKeysWithValues: states.compactMap { state -> (String, UsageInfo)? in
            guard state.error != .unauthenticated, let usage = state.usage else { return nil }
            return (usage.providerID, usage)
        })
        let enabled = LiveActivityPreferences.isEnabled(defaults: defaults)
        let activities = Activity<UsageActivityAttributes>.activities
        let ids = Set(current.keys).union(activities.map { $0.attributes.providerID })
        for id in ids {
            let oldUsage = previous[id]?.usage(providerID: id)
            let usage = current[id]
            let existing = activities.filter { $0.attributes.providerID == id }
            let first = existing.first
            let action = LiveActivityPolicy.action(previous: oldUsage, current: usage,
                                                    hasActivity: first != nil, autoStartEnabled: enabled,
                                                    manuallyStarted: first?.content.state.manuallyStarted ?? false,
                                                    lastChangedAt: first?.content.state.lastChangedAt, now: now)
            switch action {
            case .start:
                if let usage, ActivityAuthorizationInfo().areActivitiesEnabled {
                    let state = makeState(usage, previous: oldUsage, existing: nil, manual: false)
                    try? Activity.request(attributes: UsageActivityAttributes(providerID: id,
                                                                               providerName: usage.providerName),
                                          content: ActivityContent(state: state,
                                                                   staleDate: usage.lastUpdated.addingTimeInterval(3600)),
                                          pushType: nil)
                    scheduleExpiry(for: id, state: state)
                }
            case .update:
                if let usage, let first {
                    let state = makeState(usage, previous: oldUsage, existing: first.content.state,
                                          manual: first.content.state.manuallyStarted)
                    await first.update(ActivityContent(state: state,
                                                       staleDate: usage.lastUpdated.addingTimeInterval(3600)))
                    scheduleExpiry(for: id, state: state)
                }
            case .end:
                for activity in existing {
                    let reset = activity.content.state.sessionResetsAt
                    let policy: ActivityUIDismissalPolicy = reset <= now ? .after(reset) : .immediate
                    await activity.end(nil, dismissalPolicy: policy)
                }
                expiryTasks.removeValue(forKey: id)?.cancel()
            case .none: break
            }
            if action != .end {
                for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            }
        }
        let next = current.mapValues { info -> Baseline in
            let session = info.window(.session)
            return Baseline(used: session?.displayUsedPercent ?? 0,
                            resetsAt: session?.resetsAt, lastUpdated: info.lastUpdated)
        }
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: baselineKey) }
    }

    private func makeState(_ usage: UsageInfo, previous: UsageInfo?,
                           existing: UsageActivityAttributes.ContentState?, manual: Bool) -> UsageActivityAttributes.ContentState {
        let session = usage.window(.session)!
        let pace = UsagePace(window: session, now: usage.lastUpdated)
        let changed = LiveActivityPolicy.increased(previous: previous, current: usage)
        return UsageActivityAttributes.ContentState(
            sessionUsedPercent: session.displayUsedPercent,
            weeklyUsedPercent: usage.window(.weekly)?.displayUsedPercent,
            sessionResetsAt: session.resetsAt!, sessionWindowMinutes: session.windowMinutes ?? 300,
            paceStatus: .init(pace?.status), exhaustsAt: pace?.exhaustsAt,
            expectedUsedPercent: pace?.expectedUsedPercent,
            displayMode: DisplayPreferences.mode(), lastUpdated: usage.lastUpdated,
            lastChangedAt: changed ? Date() : (existing?.lastChangedAt ?? Date()), manuallyStarted: manual)
    }

    /// Best effort while this process is running; BG refresh also evaluates expiry after suspension.
    private func scheduleExpiry(for providerID: String, state: UsageActivityAttributes.ContentState) {
        expiryTasks.removeValue(forKey: providerID)?.cancel()
        let deadline = min(state.sessionResetsAt,
                           state.lastChangedAt.addingTimeInterval(LiveActivityPolicy.idleLimit))
        let delay = max(0, deadline.timeIntervalSinceNow)
        expiryTasks[providerID] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await expireIfDue(providerID: providerID)
        }
    }

    private func expireIfDue(providerID: String) async {
        let now = Date()
        for activity in Activity<UsageActivityAttributes>.activities where activity.attributes.providerID == providerID {
            let state = activity.content.state
            if state.sessionResetsAt <= now {
                await activity.end(nil, dismissalPolicy: .after(state.sessionResetsAt))
            } else if now.timeIntervalSince(state.lastChangedAt) >= LiveActivityPolicy.idleLimit {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        expiryTasks.removeValue(forKey: providerID)
    }
}
