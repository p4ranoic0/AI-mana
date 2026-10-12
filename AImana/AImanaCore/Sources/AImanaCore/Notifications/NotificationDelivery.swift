import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A phone sign-in as the planner sees it: whether one exists, and a way to check it can still be renewed.
public struct PhoneSignInProbe: Sendable {
    public let providerID: String
    let isSignedIn: @Sendable () -> Bool
    let renew: @Sendable () async throws -> Void

    public init(providerID: String, isSignedIn: @escaping @Sendable () -> Bool,
                renew: @escaping @Sendable () async throws -> Void) {
        self.providerID = providerID
        self.isSignedIn = isSignedIn
        self.renew = renew
    }
}

/// The dedupe state, as a file in the App Group. The app and the widget both deliver alerts, and a file read inside
/// the shared lock is always current, unlike another process's cached `UserDefaults`.
public struct NotificationStateFile: Sendable {
    private let url: URL
    private let legacyFallback: Bool

    /// `legacyFallback: false` for callers that never kept state in the App Group defaults (the Mac app).
    public init(url: URL, legacyFallback: Bool = true) {
        self.url = url
        self.legacyFallback = legacyFallback
    }

    public static func appGroup() -> NotificationStateFile {
        #if !canImport(Darwin)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        return NotificationStateFile(url: dir.appendingPathComponent("notification-state.json"))
    }

    /// Falls back to the state older builds kept in the shared defaults.
    public func load() -> NotificationState {
        guard let data = try? Data(contentsOf: url) else {
            return legacyFallback ? NotificationStore.state() : NotificationState()
        }
        return (try? JSONDecoder().decode(NotificationState.self, from: data)) ?? NotificationState()
    }

    public func save(_ state: NotificationState) {
        try? JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

/// Where delivery reads the user's choices and the last saved usage. The iPhone app and widget share the App Group;
/// the Mac app keeps its own copies, so its alerts are configured and deduplicated separately from the iPhone's.
public struct NotificationSettingsSource: Sendable {
    public var preferences: @Sendable () -> NotificationPreferences
    public var displayMode: @Sendable () -> DisplayMode
    /// Used to rebuild the daily summary when the settings change between refreshes.
    public var savedUsages: @Sendable () -> [UsageInfo]

    public init(preferences: @escaping @Sendable () -> NotificationPreferences,
                displayMode: @escaping @Sendable () -> DisplayMode = { .used },
                savedUsages: @escaping @Sendable () -> [UsageInfo] = { [] }) {
        self.preferences = preferences
        self.displayMode = displayMode
        self.savedUsages = savedUsages
    }

    public static let appGroup = NotificationSettingsSource(preferences: { NotificationStore.preferences() },
                                                            displayMode: { DisplayPreferences.mode() },
                                                            savedUsages: { AppGroup.snapshotStore().load() })
}

/// Hands the planner's decisions to iOS. Used by the app (foreground and background task) and by the widget after
/// it fetches on its own. Plan and save run inside a cross-process lock, so two processes can never both announce
/// the same crossing.
#if canImport(UserNotifications)
public struct NotificationDelivery: Sendable {
    private let signIns: [PhoneSignInProbe]
    /// Providers without a phone sign-in: their access is judged by what the Mac relay reports.
    private let macProviderIDs: [String]
    private let lock: any ProcessLock
    private let stateFile: NotificationStateFile
    private let settings: NotificationSettingsSource

    /// `signIns` are this iPhone's own sign-ins; `macRelayProviderIDs` are providers read only from the Mac relay, whose
    /// "sign-in expired" alerts say the Mac lost access instead.
    public init(signIns: [PhoneSignInProbe] = [], macRelayProviderIDs: [String] = [],
                lock: any ProcessLock = AppGroup.lock("notifications", timeout: 10),
                stateFile: NotificationStateFile = .appGroup(),
                settings: NotificationSettingsSource = .appGroup) {
        self.signIns = signIns
        self.macProviderIDs = macRelayProviderIDs
        self.lock = lock
        self.stateFile = stateFile
        self.settings = settings
    }

    private var center: UNUserNotificationCenter { .current() }

    /// Call after every refresh, wherever it ran.
    public func didRefresh(_ states: [ProviderState]) async {
        let initial = settings.preferences()
        let logins = Self.macLogins(states, providerIDs: macProviderIDs)
            .merging(await phoneLogins(states, probe: initial.isEnabled && initial.loginAlerts)) { mac, _ in mac }
        await deliver(states, logins: logins, loginOrigin: .phone, macLoginProviderIDs: Set(macProviderIDs),
                      quietWhenDisabled: false)
    }

    /// For a caller that judges sign-ins itself, such as the Mac app after a publish (`loginOrigin: .thisMac`).
    /// While alerts are off it only records what it saw, without touching the notification center, so turning
    /// alerts on later does not announce old crossings.
    public func didRefresh(_ states: [ProviderState], logins: [String: PhoneLoginStatus],
                           loginOrigin: LoginAlertOrigin) async {
        await deliver(states, logins: logins, loginOrigin: loginOrigin, macLoginProviderIDs: [],
                      quietWhenDisabled: true)
    }

    private func deliver(_ states: [ProviderState], logins: [String: PhoneLoginStatus], loginOrigin: LoginAlertOrigin,
                         macLoginProviderIDs: Set<String>, quietWhenDisabled: Bool) async {
        try? await lock.withLock {
            // Load, plan and save without another process in between.
            let preferences = settings.preferences()
            let plan = NotificationPlanner.plan(state: stateFile.load(), states: states, logins: logins,
                                                loginOrigin: loginOrigin, macLoginProviderIDs: macLoginProviderIDs,
                                                preferences: preferences,
                                                displayMode: settings.displayMode(), now: .now)
            stateFile.save(plan.state)
            if quietWhenDisabled, !preferences.isEnabled { return }
            for notification in plan.deliver {
                try? await center.add(request(notification))
            }
            await syncPending(plan.pending)
        }
    }

    /// Settings changed: re-derive the scheduled reset announcements and the daily summary from saved data.
    public func preferencesChanged() async {
        try? await lock.withLock {
            let pending = NotificationPlanner.pending(state: stateFile.load(), usages: settings.savedUsages(),
                                                      preferences: settings.preferences(),
                                                      displayMode: settings.displayMode(), now: .now)
            await syncPending(pending)
        }
    }

    // MARK: - Delivery

    private func syncPending(_ pending: [PlannedNotification]) async {
        let wanted = Set(pending.map(\.id))
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { id in
            NotificationPlanner.scheduledPrefixes.contains { id.hasPrefix($0) } && !wanted.contains(id)
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        // Adding with an existing identifier replaces it, which keeps the summary text current.
        for notification in pending {
            try? await center.add(request(notification))
        }
    }

    private func request(_ notification: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.threadIdentifier = notification.threadID
        content.sound = notification.kind == .dailySummary ? nil : .default
        let trigger: UNNotificationTrigger?
        switch notification.trigger {
        case .now:
            trigger = nil
        case .at(let date):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        case .daily(let hour, let minute):
            trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute),
                                                    repeats: true)
        }
        return UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
    }

    // MARK: - Phone sign-in

    /// Signed-in providers whose refresh was rejected, or whose token can no longer be renewed. A provider that fell
    /// back to the Mac relay (or, in the widget, to the saved snapshot) hides its own error, hence the extra token
    /// check (no network unless near expiry), which only runs while sign-in alerts are on.
    private func phoneLogins(_ states: [ProviderState], probe: Bool) async -> [String: PhoneLoginStatus] {
        var result: [String: PhoneLoginStatus] = [:]
        for signIn in signIns {
            let error = states.first { $0.providerID == signIn.providerID }?.error
            result[signIn.providerID] = await Self.status(signedIn: signIn.isSignedIn(), error: error,
                                                          probe: probe ? signIn.renew : nil)
        }
        return result
    }

    /// What the relay says about the Mac's access: rejected → expired, a fresh reading → active, anything else
    /// (relay unreachable, network trouble) says nothing.
    static func macLogins(_ states: [ProviderState], providerIDs: [String]) -> [String: PhoneLoginStatus] {
        var result: [String: PhoneLoginStatus] = [:]
        for id in providerIDs {
            guard let state = states.first(where: { $0.providerID == id }) else { continue }
            if state.error == .unauthenticated {
                result[id] = .expired
            } else if state.error == nil, state.usage != nil {
                result[id] = .active
            }
        }
        return result
    }

    static func status(signedIn: Bool, error: UsageProviderError?,
                       probe: (@Sendable () async throws -> Void)?) async -> PhoneLoginStatus? {
        guard signedIn else { return .signedOut }
        if error == .unauthenticated { return .expired }
        guard let probe else { return nil }
        do {
            try await probe()
            return .active
        } catch UsageProviderError.unauthenticated {
            return .expired
        } catch {
            return nil   // offline or server trouble says nothing about the sign-in
        }
    }
}
#endif
