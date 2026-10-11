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
