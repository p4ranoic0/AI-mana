import AImanaCore
import Foundation

/// Lets the widgets fetch providers with on-phone credentials while the app is closed. The Mac relay file is
/// opened through the app's security-scoped bookmark, so relay-only providers use the app's saved snapshot.
///
/// The fetch writes the same snapshot and history the app does, keeps the snapshot's relay-only fields (costs,
/// history, plan), and runs the notification planner so alerts do not wait for the app. All widgets share one fetch:
/// the first reload past the interval does it, the others find a fresh snapshot.
enum WidgetRefresher {
    /// Short timeouts keep a fetch (token renewal plus one usage request per provider, in parallel) well inside the
    /// time iOS gives a widget reload.
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 12
    private static let lockTimeout: TimeInterval = 10
    /// The timeline is handed back by then even if a request is still running; the fetch itself is never cut short,
    /// so a renewed refresh token is still saved.
    private static let deadline: TimeInterval = 25

    static func refreshIfNeeded() async {
        guard AppGroup.sharedContainerAvailable else { return }
        await withDeadline(deadline) {
            await refresh { snapshot, providerIDs, lastAttempt, now in
                RefreshSchedule.isDue(snapshot: snapshot, providerIDs: providerIDs,
                                      interval: RefreshPreferences.interval(), lastAttempt: lastAttempt, now: now)
            }
        }
    }

    /// Someone asked (the widgets' refresh button, Siri, Shortcuts): fetch when the snapshot is older than `maxAge`,
    /// whatever the chosen interval. Same fetch, lock and side effects as `refreshIfNeeded`.
    static func refreshOnDemand(maxAge: TimeInterval, deadline: TimeInterval) async {
        guard AppGroup.sharedContainerAvailable else { return }
        await withDeadline(min(deadline, Self.deadline)) {
            await refresh { snapshot, providerIDs, lastAttempt, now in
                RefreshSchedule.isDueOnDemand(snapshot: snapshot, providerIDs: providerIDs, maxAge: maxAge,
                                              lastAttempt: lastAttempt, now: now)
            }
        }
    }

    private typealias DueCheck = @Sendable (_ snapshot: [UsageInfo], _ providerIDs: [String], _ lastAttempt: Date?,
                                            _ now: Date) -> Bool

    private static func refresh(isDue due: DueCheck) async {
        let transport = URLSessionTransport(requestTimeout: requestTimeout, resourceTimeout: resourceTimeout)
        let claudeSignedIn = { false }   // public builds: Claude comes only from the Mac, through the app
        let store = AppGroup.snapshotStore()
        let openRouter = OpenRouterProvider(store: AppGroup.keychain(), transport: transport)
        let copilot = CopilotProvider(store: AppGroup.keychain(), transport: transport)
        // DeepSeek, Moonshot, xAI: balance only (no lanes); the widgets skip them, the snapshot keeps them current.
        let balances: [any UsageProvider] = BalanceDescriptor.all.map {
            BalanceProvider(descriptor: $0, store: AppGroup.keychain(), transport: transport)
        }

        // Reads the Keychain, which also answers "no" before the first unlock after a restart.
        func isDue() -> Bool {
            var signedIn = claudeSignedIn() ? ["claude"] : []
            signedIn += (openRouter.isEnabled ? [OpenRouterProvider.providerID] : [])
                + (copilot.isEnabled ? [CopilotProvider.providerID] : [])
                + balances.filter(\.isEnabled).map(\.id)
            return due(store.load(), signedIn, RefreshPreferences.lastAttempt(), .now)
        }
        guard isDue() else { return }

        try? await AppGroup.lock("widget-refresh", timeout: lockTimeout).withLock {
            guard isDue() else { return }   // another widget fetched while this one waited
            RefreshPreferences.setLastAttempt(.now)
            let saved = store.load()
            let claudeProvider: any UsageProvider = SnapshotProvider(id: "claude", displayName: "Claude Code",
                                                                     items: saved)
            let codexProvider: any UsageProvider = SnapshotProvider(id: "codex", displayName: "OpenAI Codex",
                                                                    items: saved)
            let delivery = NotificationDelivery(macRelayProviderIDs: ["claude", "codex"])
            let service = UsageService(providers: [
                claudeProvider,
                codexProvider,
                openRouter,
                copilot,
            ] + balances, store: store, history: AppGroup.historyStore())
            let states = await service.refresh()
            WidgetStatusPreferences.update(from: states)
            await delivery.didRefresh(states)
        }
    }

    /// Returns when `work` finishes or after `seconds`, whichever comes first, without cancelling `work`.
    private static func withDeadline(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> Void) async {
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await work()
                if once.claim() { continuation.resume() }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() { continuation.resume() }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
    }
}

/// WidgetKit's completion handlers are not `Sendable`; WidgetKit accepts the call from any thread.
struct SendableCompletion<Value>: @unchecked Sendable {
    let handler: (Value) -> Void
    func callAsFunction(_ value: Value) { handler(value) }
}
