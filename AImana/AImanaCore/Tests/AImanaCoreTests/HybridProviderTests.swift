import Foundation
import Testing
@testable import AImanaCore

private struct Fixed: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let result: Result<UsageInfo, UsageProviderError>
    func fetchUsage() async throws -> UsageInfo { try result.get() }
}

private let t = Date(timeIntervalSince1970: 1_800_000_000)
private func info(used: Double, plan: String? = nil, cost: CostReport? = nil, history: [HistorySeries] = []) -> UsageInfo {
    UsageInfo(providerID: "claude", providerName: "Claude Code",
              windows: [UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300, resetsAt: nil)],
              plan: plan, lastUpdated: t, cost: cost, history: history)
}
/// True on the first check, false afterwards: the user turned direct access off while the request was in flight.
private final class Checks: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Bool { lock.withLock { count += 1; return count == 1 } }
}
private let report = CostReport(providerID: "claude", generatedAt: t, days: [])
private let series = [HistorySeries(providerID: "claude", kind: .session, points: [])]

@Suite struct HybridProviderTests {
    @Test func directUsageWinsAndBorrowsRelayExtras() async throws {
        let p = HybridProvider(direct: Fixed(result: .success(info(used: 10))),
                               relay: Fixed(result: .success(info(used: 99, plan: "max", cost: report, history: series))),
                               isDirectEnabled: { true })
        let result = try await p.fetchUsage()
        #expect(result.primary?.usedPercent == 10)     // the phone's own reading, not the relay's
        #expect(result.plan == "max")
        #expect(result.cost == report)
        #expect(result.history == series)
    }

    @Test func fallsBackToRelayWhenDirectFails() async throws {
        let p = HybridProvider(direct: Fixed(result: .failure(.network)),
                               relay: Fixed(result: .success(info(used: 42))), isDirectEnabled: { true })
        do {
            _ = try await p.fetchUsage()
            Issue.record("expected a DirectFallback")
        } catch let fallback as DirectFallback {
            #expect(fallback.usage.primary?.usedPercent == 42)
            #expect(fallback.directError == .network)
        }
    }

    @Test func directFailsWithFreshRelayKeepsTheDirectError() async throws {
        let p = HybridProvider(direct: Fixed(result: .failure(.unauthenticated)),
                               relay: Fixed(result: .success(info(used: 42))), isDirectEnabled: { true })
        let fallback = try await #require(throws: DirectFallback.self) { try await p.fetchUsage() }
        #expect(fallback.directError == .unauthenticated)
        #expect(fallback.usage.primary?.usedPercent == 42)
    }

    @Test func directRateLimitedKeepsRelay() async throws {
        let until = t.addingTimeInterval(600)
        let p = HybridProvider(direct: Fixed(result: .failure(.rateLimited(until: until))),
                               relay: Fixed(result: .success(info(used: 42))), isDirectEnabled: { true })
        let fallback = try await #require(throws: DirectFallback.self) { try await p.fetchUsage() }
        #expect(fallback.directError == .rateLimited(until: until))
    }

    @Test func directFailsWithoutRelayRethrows() async {
        let p = HybridProvider(direct: Fixed(result: .failure(.server(status: 500))),
                               relay: Fixed(result: .failure(.relayUnavailable)), isDirectEnabled: { true })
        await #expect(throws: UsageProviderError.server(status: 500)) { _ = try await p.fetchUsage() }
    }

    @Test func revokedWhileInFlightDiscardsDirect() async throws {
        let checks = Checks()
        let p = HybridProvider(direct: Fixed(result: .success(info(used: 10))),
                               relay: Fixed(result: .success(info(used: 42))),
                               isDirectEnabled: { checks.next() })
        #expect(try await p.fetchUsage().primary?.usedPercent == 42)
    }

    @Test func usesRelayOnlyWhenNotSignedIn() async throws {
        let p = HybridProvider(direct: Fixed(result: .failure(.unauthenticated)),
                               relay: Fixed(result: .success(info(used: 7))), isDirectEnabled: { false })
        #expect(try await p.fetchUsage().primary?.usedPercent == 7)
    }

    @Test func directWorksEvenWithoutAnyRelay() async throws {
        let p = HybridProvider(direct: Fixed(result: .success(info(used: 10))),
                               relay: Fixed(result: .failure(.relayUnavailable)), isDirectEnabled: { true })
        let result = try await p.fetchUsage()
        #expect(result.primary?.usedPercent == 10)
        #expect(result.cost == nil && result.history.isEmpty)
    }

    @Test func reportsTheMostUsefulErrorWhenBothFail() async {
        let p = HybridProvider(direct: Fixed(result: .failure(.unauthenticated)),
                               relay: Fixed(result: .failure(.relayUnavailable)), isDirectEnabled: { true })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await p.fetchUsage() }
    }
}
