import Foundation
import Testing
@testable import AImanaCore

struct SnapshotStoreLargeTests {
    @Test func roundTripsEightDaysOfHistoryAndThirtyDaysOfCosts() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let reset = now.addingTimeInterval(5 * 3600)
        let pointCount = 8 * 24 * 4
        let points: [HistoryPoint] = (0..<pointCount).map { index in
            let time = now.addingTimeInterval(Double(index - pointCount) * 900)
            return HistoryPoint(t: time, used: Double(index % 100), resetsAt: reset)
        }
        let history: [HistorySeries] = [
            HistorySeries(providerID: "claude", kind: .session, points: points),
            HistorySeries(providerID: "claude", kind: .weekly, points: points)
        ]
        let days = (0..<30).map { offset in
            let day = UsageFormatter.localDayString(for: now.addingTimeInterval(Double(offset - 29) * 86_400),
                                                    timeZone: TimeZone(secondsFromGMT: 0)!)
            return DailyCost(day: day, tokens: TokenUsage(input: 100_000, output: 20_000),
                             usd: Double(offset) / 10, unpricedTokens: 1_000,
                             models: [ModelCost(model: "claude-sonnet", tokens: TokenUsage(input: 100_000),
                                                usd: Double(offset) / 10)])
        }
        let item = UsageInfo(providerID: "claude", providerName: "Claude Code",
                             windows: [UsageWindow(kind: .session, usedPercent: 42,
                                                   windowMinutes: 300, resetsAt: reset)],
                             plan: "max", lastUpdated: now,
                             details: [UsageDetail(kind: .cloudCredits, remaining: 12.5, limit: 20)],
                             cost: CostReport(providerID: "claude", generatedAt: now, days: days),
                             history: history)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aimana-widget-large-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnapshotStore(fileURL: url)
        try store.save([item])
        #expect((try Data(contentsOf: url)).count > 100_000)
        let loaded = store.load()
        #expect(loaded == [item])
        #expect(loaded.first?.history.first?.points.count == 8 * 24 * 4)
        #expect(loaded.first?.cost?.days.count == 30)
    }
}
