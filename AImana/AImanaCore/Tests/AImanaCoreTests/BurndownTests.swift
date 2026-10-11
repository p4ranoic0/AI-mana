import Foundation
import Testing
@testable import AImanaCore

@Suite struct BurndownTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(used: Double = 60) -> UsageWindow {
        UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300,
                    resetsAt: start.addingTimeInterval(18_000))
    }

    @Test func selectsOnlyCurrentMatchingWindowAndSorts() throws {
        let reset = start.addingTimeInterval(18_000)
        let series = [
            HistorySeries(providerID: "claude", kind: .session, points: [
                HistoryPoint(t: start.addingTimeInterval(7_200), used: 38,
                             resetsAt: reset.addingTimeInterval(120)),
                HistoryPoint(t: start.addingTimeInterval(3_600), used: 20, resetsAt: reset),
                HistoryPoint(t: start.addingTimeInterval(5_400), used: 30,
                             resetsAt: reset.addingTimeInterval(121)),
                HistoryPoint(t: start.addingTimeInterval(-1), used: 5, resetsAt: reset),
            ]),
            HistorySeries(providerID: "codex", kind: .session,
                          points: [HistoryPoint(t: start.addingTimeInterval(2_000), used: 99, resetsAt: reset)]),
            HistorySeries(providerID: "claude", kind: .weekly,
                          points: [HistoryPoint(t: start.addingTimeInterval(2_000), used: 99, resetsAt: reset)]),
        ]
        let curve = try #require(Burndown(providerID: "claude", window: window(), history: series,
                                         mode: .used, observedAt: start.addingTimeInterval(9_000)))
        #expect(curve.recordedPointCount == 2)
        #expect(curve.hasEnoughHistory)
        #expect(curve.actual.map(\.percent) == [20, 38, 60])
        #expect(curve.current?.percent == 60)
    }

    @Test func remainingReversesHistoryGuideAndProjection() throws {
        let reset = start.addingTimeInterval(18_000)
        let history = [HistorySeries(providerID: "claude", kind: .session, points: [
            HistoryPoint(t: start.addingTimeInterval(3_600), used: 10, resetsAt: reset),
            HistoryPoint(t: start.addingTimeInterval(7_200), used: 20, resetsAt: reset),
        ])]
        let curve = try #require(Burndown(providerID: "claude", window: window(used: 40), history: history,
                                         mode: .remaining, observedAt: start.addingTimeInterval(9_000)))
        #expect(curve.actual.map(\.percent) == [90, 80, 60])
        #expect(curve.guide.map(\.percent) == [100, 0])
        #expect(curve.projection.first?.percent == 60)
        #expect(curve.projection.last?.percent == 20)
    }

    @Test func fastProjectionHitsLimitBeforeResetAndFlattens() throws {
        let curve = try #require(Burndown(providerID: "claude", window: window(used: 80), history: [],
                                         mode: .used, observedAt: start.addingTimeInterval(9_000)))
        #expect(curve.projection.count == 3)
        #expect(curve.projection.map(\.percent) == [80, 100, 100])
        #expect(curve.projection[1].time < curve.end)
        #expect(!curve.hasEnoughHistory)
    }

    @Test func tooEarlyAndDepletedDoNotProject() throws {
        for (used, seconds) in [(10.0, 200.0), (100.0, 9_000.0)] {
            let curve = try #require(Burndown(providerID: "claude", window: window(used: used),
                                             history: [], mode: .used,
                                             observedAt: start.addingTimeInterval(seconds)))
            #expect(curve.projection.isEmpty)
        }
        #expect(Burndown(providerID: "claude",
                         window: UsageWindow(kind: .session, usedPercent: 20, windowMinutes: nil,
                                             resetsAt: start.addingTimeInterval(18_000)),
                         history: [], mode: .used, observedAt: start) == nil)
    }
}
