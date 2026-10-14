import Foundation
import Testing
@testable import AImanaCore

private struct ParityFixture: Decodable {
    let now: Date
    let zone: String
    let dashboard: Dashboard
    let demo: DemoExpected
    let fractional: Fractional
    let providers: [Provider]
    struct Fractional: Decodable {
        let now: String
        let window: Window
        let expected: FractionalExpected
        struct Window: Decodable {
            let kind: String
            let usedPercent: Double
            let windowMinutes: Int
            let resetsAt: String
        }
        struct FractionalExpected: Decodable {
            let perDay: Double
            let projectedUsedAtReset: Double
            let exhaustSecondsFromNow: Double
            let pace: String
            let projectionPercents: [Double]
        }
    }
    struct DemoExpected: Decodable {
        let claudeWeeklyUsedToday: Double
        let claudeWeeklyTodayAllowance: Double
        let claudeWeeklyHistoryPoints: Int
        let claudeWeeklyFirstUsed: Double
        let costClaudeTodayUSD: Double
        let costClaudeWeekUSD: Double
        let costClaudeMonthUSD: Double
        let claudeWeeklyPerDay: Double
        let claudeModelPerDay: Double
        let claudeSessionProjection: Double
        let codexWeeklyPerDay: Double
        let codexWeeklyUsedToday: Double
        let codexWeeklyTodayAllowance: Double
        let codexModelPerDay: Double
        let costCodexTodayUSD: Double
        let costCodexWeekUSD: Double
        let costCodexMonthUSD: Double
    }
    struct Dashboard: Decodable {
        let lanePercents: [Double]
        let highlightedProvider: String
        let highlightedKind: String
    }
    struct Provider: Decodable {
        let id: String
        let name: String
        let windows: [UsageWindow]
        let history: [HistorySeries]
        let cost: CostReport
        let expected: Expected
    }
    struct Expected: Decodable {
        let weeklyPerDay: Double
        let weeklyUsedToday: Double
        let weeklyTodayAllowance: Double
        let weeklyPace: String
        let weeklyProjection: Double
        let weeklyActualPercents: [Double]
        let weeklyActualTimes: [Date]
        let weeklyProjectionTimes: [Date]
        let weeklyGuidePercents: [Double]
        let costTodayUSD: Double
        let costWeekUSD: Double
        let costMonthUSD: Double
        let costTodayTokens: Int
        let costWeekTokens: Int
        let costMonthTokens: Int
    }
}

@Suite struct ParityFixtureTests {
    @Test func sharedDashboardDetailAndCosts() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Fixtures/parity/usage-costs.json").standardizedFileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(ParityFixture.self, from: Data(contentsOf: file))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: fixture.zone))
        let usages = fixture.providers.map { provider in
            UsageInfo(providerID: provider.id, providerName: provider.name, windows: provider.windows,
                      plan: nil, lastUpdated: fixture.now, cost: provider.cost, history: provider.history)
        }
        let summary = try #require(OverviewSummary(usages: usages, mode: .used))
        #expect(summary.lanes.map(\.displayPercent) == fixture.dashboard.lanePercents)
        #expect(summary.highlighted.providerID == fixture.dashboard.highlightedProvider)
        #expect(summary.highlighted.window.kind.wireValue == fixture.dashboard.highlightedKind)
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionNow = try #require(timestamp.date(from: fixture.fractional.now))
        let fractionReset = try #require(timestamp.date(from: fixture.fractional.window.resetsAt))
        let fractionWindow = UsageWindow(kind: .weekly, usedPercent: fixture.fractional.window.usedPercent,
            windowMinutes: fixture.fractional.window.windowMinutes, resetsAt: fractionReset)
        let fractionBudget = try #require(DailyBudget(window: fractionWindow, now: fractionNow, calendar: calendar))
        #expect(abs(fractionBudget.perDayPercent - fixture.fractional.expected.perDay) < 0.000001)
        let fractionPace = try #require(UsagePace(window: fractionWindow, now: fractionNow))
        #expect(String(describing: fractionPace.status) == fixture.fractional.expected.pace)
        #expect(abs((fractionPace.projectedUsedAtReset ?? -1) - fixture.fractional.expected.projectedUsedAtReset) < 0.000001)
        #expect(abs((fractionPace.exhaustsAt?.timeIntervalSince(fractionNow) ?? -1) - fixture.fractional.expected.exhaustSecondsFromNow) < 0.0001)
        let fractionCurve = try #require(Burndown(providerID: "fractional", window: fractionWindow,
            history: [], mode: .used, observedAt: fractionNow))
        #expect(fractionCurve.projection.map(\.percent) == fixture.fractional.expected.projectionPercents)
        #expect(fractionCurve.projection.count == 3)
        let demoClaude = try #require(DemoProviders.usage(now: fixture.now).first)
        let demoWeekly = try #require(demoClaude.window(.weekly))
        let demoBudget = try #require(DailyBudget(window: demoWeekly, history: demoClaude.history,
            providerID: demoClaude.providerID, now: fixture.now, calendar: DemoProviders.calendar))
        #expect(abs((demoBudget.usedToday ?? -1) - fixture.demo.claudeWeeklyUsedToday) < 0.000001)
        #expect(abs((demoBudget.todayBudgetPercent ?? -1) - fixture.demo.claudeWeeklyTodayAllowance) < 0.000001)
        #expect(demoClaude.history[0].points.count == fixture.demo.claudeWeeklyHistoryPoints)
        #expect(abs((demoClaude.history[0].points.first?.used ?? -1) - fixture.demo.claudeWeeklyFirstUsed) < 0.000001)
        let demoCost = try #require(demoClaude.cost)
        #expect(abs(demoCost.total(lastDays: 1, endingOn: "2026-10-13").usd - fixture.demo.costClaudeTodayUSD) < 0.000001)
        #expect(abs(demoCost.total(lastDays: 7, endingOn: "2026-10-13").usd - fixture.demo.costClaudeWeekUSD) < 0.000001)
        #expect(abs(demoCost.total(lastDays: 30, endingOn: "2026-10-13").usd - fixture.demo.costClaudeMonthUSD) < 0.000001)
        #expect(abs(demoBudget.perDayPercent - fixture.demo.claudeWeeklyPerDay) < 0.000001)
        let demoSonnet = try #require(demoClaude.window(.model("Sonnet")))
        let sonnetBudget = try #require(DailyBudget(window: demoSonnet, now: fixture.now))
        #expect(abs(sonnetBudget.perDayPercent - fixture.demo.claudeModelPerDay) < 0.000001)
        let demoSession = try #require(demoClaude.window(.session))
        let demoSessionPace = try #require(UsagePace(window: demoSession, now: fixture.now))
        #expect(abs((demoSessionPace.projectedUsedAtReset ?? -1) - fixture.demo.claudeSessionProjection) < 0.000001)
        let demoCodex = try #require(DemoProviders.usage(now: fixture.now).last)
        let codexWeekly = try #require(demoCodex.window(.weekly))
        let codexBudget = try #require(DailyBudget(window: codexWeekly, history: demoCodex.history,
            providerID: demoCodex.providerID, now: fixture.now, calendar: DemoProviders.calendar))
        #expect(abs(codexBudget.perDayPercent - fixture.demo.codexWeeklyPerDay) < 0.000001)
        #expect(abs((codexBudget.usedToday ?? -1) - fixture.demo.codexWeeklyUsedToday) < 0.000001)
        #expect(abs((codexBudget.todayBudgetPercent ?? -1) - fixture.demo.codexWeeklyTodayAllowance) < 0.000001)
        let codexModel = try #require(demoCodex.window(.model("GPT-5.3-Codex-Spark")))
        let codexModelBudget = try #require(DailyBudget(window: codexModel, now: fixture.now))
        #expect(abs(codexModelBudget.perDayPercent - fixture.demo.codexModelPerDay) < 0.000001)
        let codexCost = try #require(demoCodex.cost)
        #expect(abs(codexCost.total(lastDays: 1, endingOn: "2026-10-13").usd - fixture.demo.costCodexTodayUSD) < 0.000001)
        #expect(abs(codexCost.total(lastDays: 7, endingOn: "2026-10-13").usd - fixture.demo.costCodexWeekUSD) < 0.000001)
        #expect(abs(codexCost.total(lastDays: 30, endingOn: "2026-10-13").usd - fixture.demo.costCodexMonthUSD) < 0.000001)
        for (usage, provider) in zip(usages, fixture.providers) {
            let weekly = try #require(usage.window(.weekly))
            let expected = provider.expected
            let budget = try #require(DailyBudget(window: weekly, history: usage.history,
                                                  providerID: usage.providerID, now: fixture.now, calendar: calendar))
            #expect(abs(budget.perDayPercent - expected.weeklyPerDay) < 0.000001)
            #expect(abs((budget.usedToday ?? -1) - expected.weeklyUsedToday) < 0.000001)
            #expect(abs((budget.todayBudgetPercent ?? -1) - expected.weeklyTodayAllowance) < 0.000001)
            let pace = try #require(UsagePace(window: weekly, now: fixture.now))
            #expect(String(describing: pace.status) == expected.weeklyPace)
            #expect(abs((pace.projectedUsedAtReset ?? -1) - expected.weeklyProjection) < 0.000001)
            let curve = try #require(Burndown(providerID: usage.providerID, window: weekly,
                                              history: usage.history, mode: .used, observedAt: fixture.now))
            #expect(curve.actual.count == expected.weeklyActualPercents.count)
            for (actual, value) in zip(curve.actual, expected.weeklyActualPercents) {
                #expect(abs(actual.percent - value) < 0.000001)
            }
            #expect(curve.actual.map(\.time) == expected.weeklyActualTimes)
            #expect(curve.projection.map(\.time) == expected.weeklyProjectionTimes)
            #expect(curve.guide.map(\.percent) == expected.weeklyGuidePercents)
            #expect(curve.projection.count == 2)
            #expect(abs((curve.projection.last?.percent ?? -1) - min(100, expected.weeklyProjection)) < 0.000001)
            let today = provider.cost.total(lastDays: 1, endingOn: "2026-10-13")
            let week = provider.cost.total(lastDays: 7, endingOn: "2026-10-13")
            let month = provider.cost.total(lastDays: 30, endingOn: "2026-10-13")
            #expect(abs(today.usd - expected.costTodayUSD) < 0.000001)
            #expect(abs(week.usd - expected.costWeekUSD) < 0.000001)
            #expect(abs(month.usd - expected.costMonthUSD) < 0.000001)
            #expect(today.tokens.total == expected.costTodayTokens)
            #expect(week.tokens.total == expected.costWeekTokens)
            #expect(month.tokens.total == expected.costMonthTokens)
        }
    }
}
