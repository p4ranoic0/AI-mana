import Foundation
import Testing
@testable import AImanaCore

private actor CallCounter {
    var count = 0
    func hit() { count += 1 }
}

private struct SlowProvider: UsageProvider {
    let id = "slow"
    let displayName = "Slow"
    let counter: CallCounter
    func fetchUsage() async throws -> UsageInfo {
        await counter.hit()
        try await Task.sleep(for: .milliseconds(100))
        return info("slow", used: 1)
    }
}

private struct StubProvider: UsageProvider {
    let id: String
    let displayName: String
    let result: Result<UsageInfo, UsageProviderError>
    func fetchUsage() async throws -> UsageInfo { try result.get() }
}

private func info(_ id: String, used: Double, at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> UsageInfo {
    UsageInfo(providerID: id, providerName: id,
              windows: [UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300, resetsAt: nil)],
              plan: nil, lastUpdated: date)
}

private struct FallbackProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let usage: UsageInfo
    func fetchUsage() async throws -> UsageInfo {
        throw DirectFallback(usage: usage, directError: .unauthenticated)
    }
}

@Suite struct UsageServiceTests {
    @Test func fallbackNeverShowsANewerDirectSnapshotAsRelay() async throws {
        let store = makeStore()
        // The widget saved a direct reading at 12:05; the relay only has 12:00.
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try store.save([info("claude", used: 90, at: t.addingTimeInterval(300))])
        let hybrid = HybridProvider(direct: StubProvider(id: "claude", displayName: "Claude", result: .failure(.unauthenticated)),
                                    relay: StubProvider(id: "claude", displayName: "Claude", result: .success(info("claude", used: 42, at: t))),
                                    isDirectEnabled: { true })
        let state = await UsageService(providers: [hybrid], store: store, saveLock: testSaveLock()).refresh()
        #expect(state.first?.isFallback == true)
        #expect(state.first?.usage?.primary?.usedPercent == 42)
        #expect(store.load().first?.primary?.usedPercent == 42)
    }

    @Test func fallbackStateHasUsageAndError() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fallback-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let history = UsageHistoryStore(fileURL: dir.appendingPathComponent("h.json"))
        let service = UsageService(providers: [FallbackProvider(usage: info("claude", used: 42, at: Date()))],
                                   store: makeStore(), history: history, saveLock: testSaveLock())
        let state = await service.refresh()
        #expect(state.first?.usage?.primary?.usedPercent == 42)
        #expect(state.first?.error == .unauthenticated)
        #expect(state.first?.isFallback == true)
        #expect(history.load().contains { $0.providerID == "claude" && !$0.points.isEmpty })
    }

    private func makeStore() -> SnapshotStore {
        SnapshotStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString).json"))
    }

    @Test func mergesResultsInProviderOrder() async {
        let service = UsageService(
            providers: [
                StubProvider(id: "claude", displayName: "Claude", result: .success(info("claude", used: 18))),
                StubProvider(id: "codex", displayName: "Codex", result: .success(info("codex", used: 33))),
            ],
            store: makeStore(), saveLock: testSaveLock())
        let state = await service.refresh()
        #expect(state.map(\.providerID) == ["claude", "codex"])
        #expect(state[0].usage?.primary?.remainingPercent == 82)
        #expect(state[1].usage?.primary?.remainingPercent == 67)
    }

    @Test func oneFailureDoesNotAffectOthers() async {
        let service = UsageService(
            providers: [
                StubProvider(id: "claude", displayName: "Claude", result: .failure(.unauthenticated)),
                StubProvider(id: "codex", displayName: "Codex", result: .success(info("codex", used: 33))),
            ],
            store: makeStore(), saveLock: testSaveLock())
        let state = await service.refresh()
        #expect(state[0].usage == nil)
        #expect(state[0].error == .unauthenticated)
        #expect(state[1].usage != nil)
        #expect(state[1].error == nil)
    }

    @Test func keepsLastSnapshotOnTransientError() async throws {
        let store = makeStore()
        let first = info("claude", used: 18)
        try store.save([first])
        let service = UsageService(
            providers: [StubProvider(id: "claude", displayName: "Claude", result: .failure(.network))],
            store: store, saveLock: testSaveLock())
        let state = await service.refresh()
        #expect(state[0].usage == first)          // stale value, original timestamp kept
        #expect(state[0].error == .network)
    }

    @Test func authFailureDropsStaleSnapshot() async throws {
        let store = makeStore()
        try store.save([info("claude", used: 18)])
        let service = UsageService(
            providers: [StubProvider(id: "claude", displayName: "Claude", result: .failure(.unauthenticated))],
            store: store, saveLock: testSaveLock())
        let state = await service.refresh()
        #expect(state[0].usage == nil)
    }

    @Test func persistsSuccessfulResults() async {
        let store = makeStore()
        let service = UsageService(
            providers: [StubProvider(id: "claude", displayName: "Claude", result: .success(info("claude", used: 18)))],
            store: store, saveLock: testSaveLock())
        _ = await service.refresh()
        #expect(store.load().map(\.providerID) == ["claude"])
    }

    @Test func concurrentRefreshesShareOneFetch() async {
        let counter = CallCounter()
        let service = UsageService(providers: [SlowProvider(counter: counter)], store: makeStore(),
                                   saveLock: testSaveLock())
        async let a = service.refresh()
        async let b = service.refresh()
        _ = await (a, b)
        #expect(await counter.count == 1)
    }
}
