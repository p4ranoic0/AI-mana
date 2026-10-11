import Foundation

/// Outcome for one provider in a refresh: fresh data, stale data + error, or just an error.
public struct ProviderState: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let displayName: String
    public let usage: UsageInfo?
    public let error: UsageProviderError?
    public var id: String { providerID }
}

/// Fetches all providers concurrently, isolates failures, and persists the merged result. Each fresh reading is
/// also added to the phone's own history, which is merged with the relay's so both refresh paths
/// (foreground and background) build the same record.
///
/// Concurrent callers (app launch, pull-to-refresh, background task) share one in-flight refresh,
/// so a rotating refresh token is never redeemed twice at the same time.
public actor UsageService {
    private let providers: [any UsageProvider]
    private let store: SnapshotStore
    private let history: UsageHistoryStore?
    private let clock: @Sendable () -> Date
    /// Shared by the app and the widget extension: both save the whole snapshot and append to the same history
    /// file, so the read-merge-write runs under one cross-process lock (never held across network calls).
    private let saveLock: (any ProcessLock)?
    private var inFlight: Task<[ProviderState], Never>?

    public init(providers: [any UsageProvider], store: SnapshotStore, history: UsageHistoryStore? = nil,
                clock: @escaping @Sendable () -> Date = { Date() },
                saveLock: (any ProcessLock)? = AppGroup.lock("snapshot-save", timeout: 5)) {
        self.providers = providers
        self.store = store
        self.history = history
        self.clock = clock
        self.saveLock = saveLock
    }

    /// Last persisted state without touching the network.
    public func cached() -> [ProviderState] {
        let saved = Dictionary(store.load().map { ($0.providerID, $0) }, uniquingKeysWith: { _, new in new })
        return providers.filter { $0.isEnabled && (!$0.hidesWithoutData || saved[$0.id] != nil) }.map {
            ProviderState(providerID: $0.id, displayName: $0.displayName, usage: saved[$0.id], error: nil)
        }
    }

    public func refresh() async -> [ProviderState] {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.performRefresh() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performRefresh() async -> [ProviderState] {
        let previous = Dictionary(store.load().map { ($0.providerID, $0) }, uniquingKeysWith: { _, new in new })
        let providers = self.providers.filter(\.isEnabled)

        // A nil result: an opt-in relay provider that the Mac does not publish (`RelayEntryAbsent`).
        let results = await withTaskGroup(of: (Int, Result<UsageInfo, UsageProviderError>?).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do { return (index, .success(try await provider.fetchUsage())) }
                    catch let error as UsageProviderError { return (index, .failure(error)) }
                    catch let absent as RelayEntryAbsent {
                        // Not published: hidden. Unreadable file: a relay outage, which keeps the last reading if
                        // there is one and otherwise shows nothing (the user may never have turned it on).
                        let seen = previous[provider.id] != nil
                        return (index, !absent.relayReadable && seen ? .failure(.relayUnavailable) : nil)
                    }
                    catch is CancellationError { return (index, .failure(.network)) }
                    catch { return (index, .failure(.network)) }
                }
            }
            var collected: [Int: Result<UsageInfo, UsageProviderError>?] = [:]
            for await (index, result) in group { collected[index] = result }
            return collected
        }

        var states: [ProviderState] = []
        // A key removed while its request was in flight must not come back: re-check after the network wait.
        for (index, provider) in providers.enumerated() where provider.isEnabled {
            guard let result = results[index] ?? .failure(.network) else { continue }
            switch result {
            case .success(let usage):
                states.append(ProviderState(providerID: provider.id, displayName: provider.displayName,
                                            usage: usage, error: nil))
            case .failure(let error):
                let stale = error.keepsStaleData ? previous[provider.id] : nil
                states.append(ProviderState(providerID: provider.id, displayName: provider.displayName,
                                            usage: stale, error: error))
            }
        }
        if let saveLock {
            // Lock timeout or failure: save anyway rather than lose this refresh.
            let fetched = states
            if let locked = try? await saveLock.withLock({ @Sendable in self.persist(fetched) }) { return locked }
        }
        return persist(states)
    }

    /// Merges with whatever another process saved meanwhile (keeping the newer reading per provider), records
    /// history and saves. Runs under `saveLock` when there is one.
    private nonisolated func persist(_ fetched: [ProviderState]) -> [ProviderState] {
        let onDisk = Dictionary(store.load().map { ($0.providerID, $0) }, uniquingKeysWith: { _, new in new })
        var states = fetched.map { state -> ProviderState in
            guard let mine = state.usage, let theirs = onDisk[state.providerID],
                  theirs.lastUpdated > mine.lastUpdated else { return state }
            return ProviderState(providerID: state.providerID, displayName: state.displayName,
                                 usage: theirs, error: state.error)
        }
        if let history {
            let fresh = states.filter { $0.error == nil }.compactMap(\.usage)
            let local = history.record(fresh, now: clock())
            states = states.map { state in
                guard let usage = state.usage else { return state }
                let mine = local.filter { $0.providerID == usage.providerID }
                let combined = HistoryRecorder.merged(usage.history, mine)
                return ProviderState(providerID: state.providerID, displayName: state.displayName,
                                     usage: usage.withExtras(cost: usage.cost, history: combined), error: state.error)
            }
        }
        try? store.save(states.compactMap(\.usage))
        return states
    }
}
