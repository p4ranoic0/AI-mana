#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

private struct BodyTransport: HTTPTransport {
    let body: String
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private struct AnyToken: AccessTokenSource {
    func credentials() async throws -> AccessCredential { AccessCredential(token: "t", accountID: "a") }
}

/// 2027-01-15 08:00:00 UTC; local midnight (UTC) is 8 h earlier.
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let en = Locale(identifier: "en_US")
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()

private func weekly(_ used: Double, resetIn: TimeInterval, kind: UsageWindow.Kind = .weekly) -> UsageWindow {
    UsageWindow(kind: kind, usedPercent: used, windowMinutes: 10080, resetsAt: t0.addingTimeInterval(resetIn))
}

// MARK: - Daily budget

@Suite struct DailyBudgetTests {
    @Test func spreadsRemainingOverDaysLeft() throws {
        // 60 % left, 4 days to go → 15 % per day.
        let budget = try #require(DailyBudget(window: weekly(40, resetIn: 4 * 86400), now: t0, calendar: utc))
        #expect(budget.status == .spread)
        #expect(abs(budget.perDayPercent - 15) < 0.001)
        #expect(abs(budget.daysLeft - 4) < 0.001)
        #expect(budget.headline(locale: en) == "15% per day")
        #expect(budget.caption(now: t0, locale: en) == "For the next 4d to land at 100%")
        #expect(budget.usedToday == nil)
        #expect(budget.compactText(locale: en) == "15%/day")
    }

    @Test func underADayLeftAllowsEverythingRemaining() throws {
        let budget = try #require(DailyBudget(window: weekly(70, resetIn: 6 * 3600), now: t0, calendar: utc))
        #expect(budget.status == .lastDay)
        #expect(abs(budget.perDayPercent - 30) < 0.001)
        #expect(budget.headline(locale: en) == "30% until reset")
        #expect(budget.caption(now: t0, locale: en) == "Resets in 6h")
    }

    @Test func depletedAndOutdated() throws {
        let depleted = try #require(DailyBudget(window: weekly(104, resetIn: 2 * 86400), now: t0, calendar: utc))
        #expect(depleted.status == .depleted)
        #expect(depleted.perDayPercent == 0)
        #expect(depleted.headline(locale: en) == "Used up")
        let outdated = try #require(DailyBudget(window: weekly(20, resetIn: -60), now: t0, calendar: utc))
        #expect(outdated.status == .outdated)
        #expect(outdated.todayText(locale: en) == nil)
    }

    @Test func sessionsAndWindowsWithoutResetHaveNoBudget() {
        let session = UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: t0.addingTimeInterval(3600))
        #expect(DailyBudget(window: session, now: t0) == nil)
        #expect(DailyBudget(window: UsageWindow(kind: .weekly, usedPercent: 10, windowMinutes: 10080, resetsAt: nil), now: t0) == nil)
    }

    @Test func todayComparesWithReadingAtMidnight() throws {
        let reset = t0.addingTimeInterval(3 * 86400)
        let midnight = utc.startOfDay(for: t0)
        let history = [HistorySeries(providerID: "claude", kind: .weekly, points: [
            HistoryPoint(t: midnight.addingTimeInterval(-3 * 3600), used: 30, resetsAt: reset), // baseline
            HistoryPoint(t: midnight.addingTimeInterval(3600), used: 33, resetsAt: reset),
            HistoryPoint(t: midnight.addingTimeInterval(-20 * 3600), used: 20, resetsAt: reset), // too old
        ])]
        let budget = try #require(DailyBudget(window: weekly(36, resetIn: 3 * 86400), history: history,
                                              providerID: "claude", now: t0, calendar: utc))
        // At midnight: 70 % left over 3 d 8 h → 21 %/day. Spent since: 6 %.
        let expected = 70 / ((3 * 86400 + 8 * 3600) / 86400.0)
        #expect(abs((budget.todayBudgetPercent ?? 0) - expected) < 0.001)
        #expect(abs((budget.usedToday ?? 0) - 6) < 0.001)
        #expect(budget.todayText(locale: en) == "Today 6% of 21%")
        #expect(budget.compactText(locale: en) == "21%/day · today 6%")
    }

    @Test func todayIgnoresReadingsFromAnotherWindowOrProvider() throws {
        let midnight = utc.startOfDay(for: t0)
        let history = [
            HistorySeries(providerID: "claude", kind: .weekly, points: [
                HistoryPoint(t: midnight.addingTimeInterval(-600), used: 30, resetsAt: t0.addingTimeInterval(-86400))]),
            HistorySeries(providerID: "codex", kind: .weekly, points: [
                HistoryPoint(t: midnight.addingTimeInterval(-600), used: 30, resetsAt: t0.addingTimeInterval(3 * 86400))]),
        ]
        let budget = try #require(DailyBudget(window: weekly(36, resetIn: 3 * 86400), history: history,
                                              providerID: "claude", now: t0, calendar: utc))
        #expect(budget.usedToday == nil)
    }

    @Test func windowThatStartedTodayCountsFromZero() throws {
        // Weekly window started 2 h ago (after midnight): everything used is today's.
        let budget = try #require(DailyBudget(window: weekly(5, resetIn: 7 * 86400 - 7200), history: [],
                                              providerID: "claude", now: t0, calendar: utc))
        #expect(budget.usedToday == 5)
        #expect(abs((budget.todayBudgetPercent ?? 0) - 100 / 7) < 0.001)
    }
}

// MARK: - Claude extra usage

@Suite struct ClaudeExtraUsageTests {
    static let base = #""five_hour":{"utilization":9,"resets_at":"2027-01-15T10:00:00Z"}"#

    private func claude(_ body: String) async throws -> UsageInfo {
        try await ClaudeProvider(transport: BodyTransport(body: body), tokens: AnyToken(), clock: { t0 }).fetchUsage()
    }

    @Test func mapsCentsToDollars() async throws {
        // CodexBar fixture: monthly_limit 600 / used 434.43 cents, utilization 72.
        let info = try await claude(#"{\#(Self.base),"extra_usage":{"is_enabled":true,"monthly_limit":600,"used_credits":434.43,"utilization":72,"currency":"USD"}}"#)
        let extra = try #require(info.details.first { $0.kind == .extraUsage })
        #expect(abs((extra.used ?? 0) - 4.3443) < 0.0001)
        #expect(extra.limit == 6)
        #expect(abs(extra.remaining - 1.6557) < 0.0001)
        #expect(abs((extra.usedFraction ?? 0) - 0.724) < 0.001)
        #expect(extra.summary(locale: en) == "$4.34 of $6.00 this month")
        #expect(extra.title == CoreStrings.text("Extra usage"))
    }

    @Test func keepsCloudCreditsSeparate() async throws {
        let body = #"{\#(Self.base),"iguana_necktie":{"limit_dollars":100,"used_dollars":25,"remaining_dollars":75},"extra_usage":{"is_enabled":true,"monthly_limit":2000,"used_credits":500}}"#
        let info = try await claude(body)
        #expect(info.details.map(\.kind) == [.cloudCredits, .extraUsage])
        #expect(info.details.first { $0.kind == .extraUsage }?.currency == "USD")
    }

    @Test func noCapStillShowsSpend() async throws {
        let info = try await claude(#"{\#(Self.base),"extra_usage":{"is_enabled":true,"monthly_limit":null,"used_credits":1250}}"#)
        let extra = try #require(info.details.first)
        #expect(extra.limit == nil)
        #expect(extra.usedFraction == nil)
        #expect(extra.summary(locale: en) == "$12.50 spent this month")
    }

    @Test func disabledOrMalformedIsHidden() async throws {
        for fragment in [
            #""extra_usage":{"is_enabled":false,"monthly_limit":2000,"used_credits":500}"#,
            #""extra_usage":{"monthly_limit":2000,"used_credits":500}"#,
            #""extra_usage":{"is_enabled":true}"#,
            #""extra_usage":{"is_enabled":"yes","used_credits":"lots"}"#,
            #""extra_usage":[1,2]"#,
            #""extra_usage":null"#,
        ] {
            let info = try await claude("{\(Self.base),\(fragment)}")
            #expect(info.details.isEmpty, "fragment: \(fragment)")
            #expect(info.window(.session) != nil)
        }
    }

    @Test func spendOnlyAccountDecodes() async throws {
        let info = try await claude(#"{"five_hour":null,"seven_day":null,"extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":100}}"#)
        #expect(info.windows.isEmpty)
        #expect(info.details.count == 1)
    }
}

// MARK: - Codex additional limits

@Suite struct CodexAdditionalLimitTests {
    private func codex(_ body: String) async throws -> UsageInfo {
        try await CodexProvider(transport: BodyTransport(body: body), tokens: AnyToken(), clock: { t0 }).fetchUsage()
    }

    static let main = #""rate_limit":{"primary_window":{"used_percent":22,"limit_window_seconds":18000,"reset_after_seconds":3600,"reset_at":1800003600},"secondary_window":{"used_percent":43,"limit_window_seconds":604800,"reset_after_seconds":90000,"reset_at":1800090000}}"#

    @Test func mapsSparkStyleLimitToExtraLanes() async throws {
        // Shape from openai/codex `AdditionalRateLimitDetails` and CodexBar's Spark fixture.
        let body = #"{"plan_type":"pro",\#(Self.main),"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"gpt_5_3_codex_spark","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":30,"limit_window_seconds":18000,"reset_after_seconds":0,"reset_at":1800003600},"secondary_window":{"used_percent":80,"limit_window_seconds":604800,"reset_after_seconds":0,"reset_at":1800090000}}}]}"#
        let info = try await codex(body)
        #expect(info.window(.session)?.usedPercent == 22)
        #expect(info.window(.weekly)?.usedPercent == 43)
        #expect(info.window(.modelSession("GPT-5.3-Codex-Spark"))?.usedPercent == 30)
        #expect(info.window(.modelSession("GPT-5.3-Codex-Spark"))?.windowMinutes == 300)
        #expect(info.window(.model("GPT-5.3-Codex-Spark"))?.usedPercent == 80)
        #expect(info.primary?.kind == .session)
        #expect(info.windows.count == 4)
    }

    @Test func malformedEntriesAreSkipped() async throws {
        let body = #"{\#(Self.main),"additional_rate_limits":[{"limit_name":"","rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":18000,"reset_at":1}}},{"limit_name":"Broken","rate_limit":{"primary_window":{"used_percent":"x"}}},"garbage",{"metered_feature":"feature_x","rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_at":1800090000}}}]}"#
        let info = try await codex(body)
        #expect(info.windows.count == 3)
        #expect(info.window(.model("feature_x"))?.usedPercent == 5)
    }

    @Test func nonArrayAdditionalLimitsDoNotBreakResponse() async throws {
        let info = try await codex(#"{\#(Self.main),"additional_rate_limits":{"oops":true}}"#)
        #expect(info.windows.count == 2)
    }

    @Test func modelSessionKindRoundTripsAndUnknownKindsAreSkipped() throws {
        #expect(UsageWindow.Kind(wireValue: "model-session:Spark") == .modelSession("Spark"))
        #expect(UsageWindow.Kind.modelSession("Spark").wireValue == "model-session:Spark")
        #expect(UsageWindow.Kind(wireValue: "model:Spark") == .model("Spark"))
        let json = #"{"providerID":"codex","providerName":"Codex","lastUpdated":0,"windows":[{"kind":"session","usedPercent":5},{"kind":"future:lane","usedPercent":9}]}"#
        let info = try JSONDecoder().decode(UsageInfo.self, from: Data(json.utf8))
        #expect(info.windows.map(\.kind) == [.session])
    }
}

// MARK: - History on the phone

@Suite struct PhoneHistoryTests {
    private func usage(_ id: String = "claude", session: Double, weekly: Double, at date: Date) -> UsageInfo {
        UsageInfo(providerID: id, providerName: id, windows: [
            UsageWindow(kind: .session, usedPercent: session, windowMinutes: 300, resetsAt: t0.addingTimeInterval(3600)),
            UsageWindow(kind: .weekly, usedPercent: weekly, windowMinutes: 10080, resetsAt: t0.addingTimeInterval(86400)),
        ], plan: nil, lastUpdated: date)
    }

    @Test func recordUsesReadingTimeAndSkipsRepeats() {
        var s = HistoryRecorder.record([], with: [usage(session: 10, weekly: 30, at: t0)], now: t0)
        // Same relay snapshot read again later: not a new reading.
        s = HistoryRecorder.record(s, with: [usage(session: 10, weekly: 30, at: t0)], now: t0.addingTimeInterval(3600))
        #expect(s.first { $0.kind == .session }?.points.count == 1)
        s = HistoryRecorder.record(s, with: [usage(session: 15, weekly: 31, at: t0.addingTimeInterval(300))],
                                   now: t0.addingTimeInterval(3600))
        let points = s.first { $0.kind == .session }?.points ?? []
        #expect(points.map(\.used) == [10, 15])
        #expect(points.last?.t == t0.addingTimeInterval(300))
    }

    @Test func mergePrefersDenserSeriesAndFillsGaps() {
        let relay = HistorySeries(providerID: "claude", kind: .weekly, points: (0..<6).map {
            HistoryPoint(t: t0.addingTimeInterval(Double($0) * 300), used: Double($0), resetsAt: nil)
        })
        let phone = HistorySeries(providerID: "claude", kind: .weekly, points: [
            HistoryPoint(t: t0.addingTimeInterval(310), used: 1.2, resetsAt: nil),   // duplicate moment
            HistoryPoint(t: t0.addingTimeInterval(7200), used: 9, resetsAt: nil),    // fills a gap
        ])
        let codex = HistorySeries(providerID: "codex", kind: .session, points: [HistoryPoint(t: t0, used: 1, resetsAt: nil)])
        let merged = HistoryRecorder.merged([relay], [phone, codex])
        let weekly = merged.first { $0.providerID == "claude" }?.points ?? []
        #expect(weekly.count == 7)
        #expect(weekly.map(\.used).contains(1))
        #expect(!weekly.map(\.used).contains(1.2))
        #expect(weekly.last?.used == 9)
        #expect(merged.count == 2)
    }

    @Test func storeRoundTripsAndToleratesUnknownKinds() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID().uuidString).json")
        let store = UsageHistoryStore(fileURL: url)
        #expect(store.load().isEmpty)
        let recorded = store.record([usage(session: 10, weekly: 30, at: t0)], now: t0)
        #expect(store.load() == recorded)
        #expect(recorded.count == 2)
        let mixed = #"[{"providerID":"claude","kind":"future:x","points":[]},{"providerID":"claude","kind":"weekly","points":[{"t":"2027-01-15T08:00:00Z","used":3}]}]"#
        try Data(mixed.utf8).write(to: url)
        #expect(store.load().map(\.kind) == [.weekly])
    }

    @Test func serviceRecordsFreshReadingsAndMergesWithRelayHistory() async {
        struct Stub: UsageProvider {
            let id = "claude"
            let displayName = "Claude"
            let usage: UsageInfo
            func fetchUsage() async throws -> UsageInfo { usage }
        }
        let relayHistory = [HistorySeries(providerID: "claude", kind: .weekly, points: [
            HistoryPoint(t: t0.addingTimeInterval(-7200), used: 20, resetsAt: t0.addingTimeInterval(86400))])]
        let fromProvider = usage(session: 10, weekly: 30, at: t0).withExtras(cost: nil, history: relayHistory)
        let dir = FileManager.default.temporaryDirectory
        let history = UsageHistoryStore(fileURL: dir.appendingPathComponent("h-\(UUID().uuidString).json"))
        let service = UsageService(providers: [Stub(usage: fromProvider)],
                                   store: SnapshotStore(fileURL: dir.appendingPathComponent("s-\(UUID().uuidString).json")),
                                   history: history, clock: { t0 }, saveLock: testSaveLock())
        let states = await service.refresh()
        let weekly = states[0].usage?.history.first { $0.kind == .weekly }?.points ?? []
        #expect(weekly.map(\.used) == [20, 30])
        #expect(history.load().first { $0.kind == .weekly }?.points.map(\.used) == [30])
        #expect(states[0].usage?.history.contains { $0.kind == .session } == true)
    }
}

// MARK: - Insights

@Suite struct UsageInsightsTests {
    @Test func countsDistinctExhaustedSessionsThisWeek() {
        let weeklyWindow = weekly(60, resetIn: 2 * 86400)   // started 5 days ago
        let points: [HistoryPoint] = [
            // exhausted twice in one session instance → one exhaustion
            HistoryPoint(t: t0.addingTimeInterval(-86400), used: 100, resetsAt: t0.addingTimeInterval(-80000)),
            HistoryPoint(t: t0.addingTimeInterval(-85000), used: 101, resetsAt: t0.addingTimeInterval(-80000) + 30),
            HistoryPoint(t: t0.addingTimeInterval(-3600), used: 100, resetsAt: t0.addingTimeInterval(600)),
            HistoryPoint(t: t0.addingTimeInterval(-7200), used: 70, resetsAt: t0.addingTimeInterval(9000)),
            // before this weekly window started
            HistoryPoint(t: t0.addingTimeInterval(-6 * 86400), used: 100, resetsAt: t0.addingTimeInterval(-6 * 86400 + 600)),
        ]
        let insights = UsageInsights(providerID: "claude",
                                     history: [HistorySeries(providerID: "claude", kind: .session, points: points)],
                                     weekly: weeklyWindow, now: t0, calendar: utc)
        #expect(insights.sessionExhaustions == 2)
        #expect(insights.hasSessionHistory)
    }

    @Test func peakHoursSpreadGrowthOverClockHours() {
        let reset = t0.addingTimeInterval(3 * 86400)
        let midnight = utc.startOfDay(for: t0)
        func at(_ hour: Double, _ used: Double) -> HistoryPoint {
            HistoryPoint(t: midnight.addingTimeInterval(-86400 + hour * 3600), used: used, resetsAt: reset)
        }
        let series = HistorySeries(providerID: "claude", kind: .weekly, points: [
            at(13.5, 10), at(14.5, 16),   // 6 % split 3/3 between 13h and 14h
            at(15, 18),                   // +2 in 14h
            at(15, 18), at(21, 18),       // flat
            at(22, 19),                   // +1 in 21h
            at(30, 40),                   // 8 h gap: not placed
        ])
        let insights = UsageInsights(providerID: "claude", history: [series], now: t0, calendar: utc)
        #expect(abs(insights.hourlyIncrease[13] - 3) < 0.001)
        #expect(abs(insights.hourlyIncrease[14] - 5) < 0.001)
        #expect(abs(insights.hourlyIncrease[21] - 1) < 0.001)
        #expect(insights.hourlyIncrease.reduce(0, +) < 9.01)
        #expect(insights.peakHours(limit: 2) == [14, 13])
        #expect(insights.hasHourlyPattern)
        #expect(!insights.hasSessionHistory)
        #expect(insights.sessionExhaustions == 0)
    }

    @Test func weeklyResetDoesNotCountAsNegativeOrPositiveGrowth() {
        let series = HistorySeries(providerID: "claude", kind: .weekly, points: [
            HistoryPoint(t: t0.addingTimeInterval(-7200), used: 90, resetsAt: t0.addingTimeInterval(-3600)),
            HistoryPoint(t: t0.addingTimeInterval(-3000), used: 5, resetsAt: t0.addingTimeInterval(7 * 86400 - 3600)),
        ])
        let insights = UsageInsights(providerID: "claude", history: [series], now: t0, calendar: utc)
        #expect(insights.hourlyIncrease.allSatisfy { $0 == 0 })
        #expect(!insights.hasHourlyPattern)
        #expect(insights.peakHours().isEmpty)
    }
}
#endif
