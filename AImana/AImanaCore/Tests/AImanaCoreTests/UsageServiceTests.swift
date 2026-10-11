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

@Suite struct UsageServiceTests {
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
            store: makeStore())
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
            store: makeStore())
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
            store: store)
        let state = await service.refresh()
        #expect(state[0].usage == first)          // stale value, original timestamp kept
        #expect(state[0].error == .network)
    }

    @Test func authFailureDropsStaleSnapshot() async throws {
        let store = makeStore()
        try store.save([info("claude", used: 18)])
        let service = UsageService(
            providers: [StubProvider(id: "claude", displayName: "Claude", result: .failure(.unauthenticated))],
            store: store)
        let state = await service.refresh()
        #expect(state[0].usage == nil)
    }

    @Test func persistsSuccessfulResults() async {
        let store = makeStore()
        let service = UsageService(
            providers: [StubProvider(id: "claude", displayName: "Claude", result: .success(info("claude", used: 18)))],
            store: store)
        _ = await service.refresh()
        #expect(store.load().map(\.providerID) == ["claude"])
    }

    @Test func concurrentRefreshesShareOneFetch() async {
        let counter = CallCounter()
        let service = UsageService(providers: [SlowProvider(counter: counter)], store: makeStore())
        async let a = service.refresh()
        async let b = service.refresh()
        _ = await (a, b)
        #expect(await counter.count == 1)
    }
}
