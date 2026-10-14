import Foundation

/// Fixed sample data for `-demo` launches (simulator screenshots, UI work without a relay file).
public enum DemoProviders {
    /// Stable screenshot clock shared with Android. 13 Oct 2026, 13:00 in Lima.
    public static let referenceDate = Date(timeIntervalSince1970: 1791914400)

    public static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    public static func displayNow(_ live: Date = Date()) -> Date { isActive ? referenceDate : live }
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        return calendar
    }

    public static var displayCalendar: Calendar { isActive ? calendar : .current }

    struct Demo: UsageProvider {
        let id: String
        let displayName: String
        let plan: String?
        let windows: [(UsageWindow.Kind, Double, TimeInterval, Int)]
        var details: [UsageDetail] = []
        /// How much faster the 5-hour lane fills than the weekly one; high values produce exhausted sessions.
        var sessionGain = 6.0

        func fetchUsage() async throws -> UsageInfo {
            usage(now: DemoProviders.referenceDate)
        }

        func usage(now: Date) -> UsageInfo {
            let lanes = windows.map { UsageWindow(kind: $0.0, usedPercent: $0.1,
                                                  windowMinutes: $0.3, resetsAt: now.addingTimeInterval($0.2)) }
            return UsageInfo(providerID: id, providerName: displayName, windows: lanes, plan: plan,
                             lastUpdated: now, details: details,
                             cost: ["claude", "codex"].contains(id) ? DemoProviders.costReport(id, now: now) : nil,
                             history: DemoProviders.history(providerID: id, lanes: lanes, sessionGain: sessionGain, now: now),
                             source: id == "claude" ? .statusline : id == "codex" ? .logs : nil)
        }
    }

    public static let all: [any UsageProvider] = [
        Demo(id: "claude", displayName: "Claude Code", plan: "Max",
             windows: [(.session, 18, 3 * 3600 + 15 * 60, 300), (.weekly, 42, 4 * 86400 + 3600, 10080),
                       (.model("Sonnet"), 7.5, 4 * 86400 + 3600, 10080)],
             details: [UsageDetail(kind: .extraUsage, remaining: 15.66, limit: 20, currency: "USD", used: 4.34)],
             sessionGain: 11),
        Demo(id: "codex", displayName: "OpenAI Codex", plan: "Pro",
             windows: [(.session, 33, 5 * 3600 + 22 * 60, 300), (.weekly, 61, 2 * 86400 + 7200, 10080),
                       (.modelSession("GPT-5.3-Codex-Spark"), 12, 2 * 3600, 300),
                       (.model("GPT-5.3-Codex-Spark"), 27, 2 * 86400 + 7200, 10080)],
             sessionGain: 22),
        Demo(id: "openrouter", displayName: "OpenRouter", plan: nil,
             windows: [(.spendLimit, 38.4, 17 * 86400 + 5 * 3600, 30 * 1440),
                       (.freeRequests, 12, 9 * 3600, 1440)],
             details: [UsageDetail(kind: .creditBalance, remaining: 42.18, limit: 60, currency: "USD", used: 17.82),
                       UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 19.20)]),
        // AI credits used this month against the plan's included credits ($15.68 of Pro+'s $70).
        Demo(id: "copilot", displayName: "GitHub Copilot", plan: "Pro+",
             windows: [(.spendLimit, 22.4, 23 * 86400 + 6 * 3600, 31 * 1440)],
             details: [UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 15.68)]),
        // Balance-only providers: no lanes, one balance per currency as reported (DeepSeek keeps CNY and USD apart).
        Demo(id: "deepseek", displayName: "DeepSeek", plan: nil, windows: [],
             details: [UsageDetail(kind: .creditBalance, remaining: 86.40, currency: "CNY"),
                       UsageDetail(kind: .creditBalance, remaining: 4.75, currency: "USD")]),
        Demo(id: "moonshot", displayName: "Moonshot (Kimi)", plan: nil, windows: [],
             details: [UsageDetail(kind: .creditBalance, remaining: 49.59, currency: "USD")]),
        Demo(id: "xai", displayName: "xAI", plan: nil, windows: [],
             details: [UsageDetail(kind: .creditBalance, remaining: 0, currency: "USD", usable: 0)]),
    ]

    /// The same Claude and Codex readings on iPhone, Mac, and Watch screenshots.
    public static func usage(now: Date = Date()) -> [UsageInfo] {
        all.compactMap { $0 as? Demo }.filter { ["claude", "codex"].contains($0.id) }
            .map { $0.usage(now: now) }
    }

    public static func watchPayload(now: Date = Date()) -> WatchPayload {
        WatchPayload(snapshot: usage(now: now), mode: .used, now: now)
    }

    public static func macEnvelope(now: Date = Date()) -> RelayEnvelope {
        let entries = usage(now: now).map {
            RelayEntry(providerID: $0.providerID, usage: $0, error: nil)
        }
        return RelayEnvelope(generatedAt: now, entries: entries,
                             costs: [costReport("claude", now: now), costReport("codex", now: now)])
    }

    private static func costReport(_ id: String, now: Date) -> CostReport {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Lima")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let days = (0..<30).reversed().compactMap { offset -> DailyCost? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let recent = offset == 0
            let primary = id == "claude" ? "Claude Sonnet 4.5" : "GPT-5.3-Codex"
            let secondary = id == "claude" ? "Claude Opus 4.1" : "GPT-5.3-Codex-Spark"
            let base = id == "claude" ? 2.35 : 1.72
            let usd = recent ? base : base * (0.5 + Double(offset % 5) * 0.12)
            let first = ModelCost(model: primary, tokens: TokenUsage(input: 42_000, output: 8_000,
                                                                      cacheRead: 110_000), usd: usd * 0.8)
            let second = ModelCost(model: secondary, tokens: TokenUsage(input: 9_000, output: 2_000),
                                   usd: usd * 0.2)
            return DailyCost(day: formatter.string(from: date), tokens: first.tokens + second.tokens,
                             usd: usd, unpricedTokens: 0, models: [first, second])
        }
        return CostReport(providerID: id, generatedAt: now, days: days)
    }

    /// Plausible readings every 20 minutes since the weekly window began: work-hour bursts that end at the
    /// current weekly value, with 5-hour sessions that fill `sessionGain` times faster (and may run out).
    static func history(providerID: String, lanes: [UsageWindow], sessionGain: Double, now: Date) -> [HistorySeries] {
        guard let weekly = lanes.first(where: { $0.kind == .weekly }), let weeklyReset = weekly.resetsAt,
              let minutes = weekly.windowMinutes else { return [] }
        let start = max(weeklyReset.addingTimeInterval(-TimeInterval(minutes) * 60), now.addingTimeInterval(-7 * 86400))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        let step: TimeInterval = 20 * 60
        var times: [Date] = []
        var t = start
        while t < now { times.append(t); t += step }
        func activity(_ date: Date) -> Double {
            let hour = calendar.component(.hour, from: date)
            let day = calendar.ordinality(of: .day, in: .era, for: calendar.startOfDay(for: date)) ?? 0
            switch hour {
            case 10...12: return 1.0 + Double(day % 3) * 0.2
            case 14...17: return 1.6 + Double(day % 2) * 0.5
            case 21...22: return day % 2 == 0 ? 0.7 : 0
            default: return 0
            }
        }
        let raw = times.map(activity)
        let total = max(0.001, raw.reduce(0, +))
        let scale = weekly.displayUsedPercent / total
        var weeklyPoints: [HistoryPoint] = []
        var sessionPoints: [HistoryPoint] = []
        var used = 0.0
        var sessionUsed = 0.0
        var sessionReset: Date?
        for (time, act) in zip(times, raw) {
            used += act * scale
            if act > 0 {
                if sessionReset == nil || time >= sessionReset! { sessionReset = time.addingTimeInterval(5 * 3600); sessionUsed = 0 }
                sessionUsed = min(100, sessionUsed + act * scale * sessionGain)
            }
            weeklyPoints.append(HistoryPoint(t: time, used: used, resetsAt: weeklyReset))
            if let reset = sessionReset, time < reset {
                sessionPoints.append(HistoryPoint(t: time, used: sessionUsed, resetsAt: reset))
            }
        }
        return [HistorySeries(providerID: providerID, kind: .weekly, points: weeklyPoints),
                HistorySeries(providerID: providerID, kind: .session, points: sessionPoints)]
    }
}
