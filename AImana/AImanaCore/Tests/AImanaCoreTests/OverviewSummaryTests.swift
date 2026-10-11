import Foundation
import Testing
@testable import AImanaCore

@Suite struct OverviewSummaryTests {
    private func usage(_ id: String, session: Double?, weekly: Double?) -> UsageInfo {
        let windows: [UsageWindow] = [
            session.map { UsageWindow(kind: .session, usedPercent: $0, windowMinutes: 300, resetsAt: nil) },
            weekly.map { UsageWindow(kind: .weekly, usedPercent: $0, windowMinutes: 10_080, resetsAt: nil) }
        ].compactMap { $0 }
        return UsageInfo(providerID: id, providerName: id, windows: windows,
                         plan: nil, lastUpdated: .now)
    }

    @Test func choosesHighestUsedAndLowestRemainingFromCurrentLanes() throws {
        let usages = [usage("claude", session: 43, weekly: 41),
                      usage("codex", session: 49, weekly: 68)]
        let used = try #require(OverviewSummary(usages: usages, mode: .used))
        let remaining = try #require(OverviewSummary(usages: usages, mode: .remaining))
        #expect(used.lanes.map(\.id) == ["claude:session", "claude:weekly", "codex:session", "codex:weekly"])
        #expect(used.highlighted.id == "codex:weekly")
        #expect(used.highlighted.displayPercent == 68)
        #expect(remaining.highlighted.id == "codex:weekly")
        #expect(remaining.highlighted.displayPercent == 32)
    }

    @Test func omitsMissingLanesAndKeepsFirstOnTie() throws {
        let summary = try #require(OverviewSummary(usages: [usage("claude", session: nil, weekly: 50),
                                                           usage("codex", session: 50, weekly: nil)], mode: .used))
        #expect(summary.lanes.count == 2)
        #expect(summary.highlighted.id == "claude:weekly")
        #expect(OverviewSummary(usages: [usage("empty", session: nil, weekly: nil)], mode: .used) == nil)
    }

    @Test func limitsOverviewToTwoProvidersAndClampsPercent() throws {
        let summary = try #require(OverviewSummary(usages: [usage("a", session: 120, weekly: 20),
                                                           usage("b", session: 30, weekly: 40),
                                                           usage("c", session: 90, weekly: 90)], mode: .used))
        #expect(summary.lanes.count == 4)
        #expect(summary.highlighted.id == "a:session")
        #expect(summary.highlighted.displayPercent == 100)
    }
}
