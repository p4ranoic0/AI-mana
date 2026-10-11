import AImanaCore
import Foundation

/// Composition root: the only place that knows which providers exist and where their data comes from.
@MainActor
final class AppEnvironment {
    /// One per process: the app's scene and the intents Siri and the widgets run in the app share it, so a refresh
    /// started by either shows up in the other.
    static let shared = AppEnvironment()

    let service: UsageService
    private(set) lazy var dashboard = DashboardViewModel(service: service)

    /// Whether a relay file is reachable without the user picking one: a debug `-relay-file` path or `-demo` data.
    nonisolated static var hasRelayOverride: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-demo") || args.contains("-relay-file")
    }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let providers: [any UsageProvider]
        if args.contains("-demo") {
            // `-demo-providers openrouter,codex` limits the sample to those providers (screenshots of one card).
            if let i = args.firstIndex(of: "-demo-providers"), args.indices.contains(i + 1) {
                let ids = Set(args[i + 1].split(separator: ",").map(String.init))
                providers = DemoProviders.all.filter { ids.contains($0.id) }
            } else {
                providers = DemoProviders.all
            }
        } else {
            // `-relay-file <path>` reads a plain file (simulator / debugging); otherwise the bookmarked iCloud Drive file.
            let source: any RelayDataSource
            if let i = args.firstIndex(of: "-relay-file"), args.indices.contains(i + 1) {
                source = CoordinatedFileSource(url: URL(fileURLWithPath: args[i + 1]))
            } else {
                source = BookmarkRelaySource()
            }
            let codex: any UsageProvider = RelayProvider(id: "codex", displayName: "OpenAI Codex", source: source)
            // Use the Mac relay when device credentials are unavailable.
            let claude: any UsageProvider = RelayProvider(id: "claude", displayName: "Claude Code", source: source)
            // OpenRouter: the user's own API key, official API; hidden until a key is saved in Settings.
            let openRouter = OpenRouterProvider(store: AppGroup.keychain())
            // GitHub Copilot: the user's own token, GitHub's official billing API; hidden until a token is saved.
            let copilot = CopilotProvider(store: AppGroup.keychain())
            // DeepSeek, Moonshot (Kimi), xAI: prepaid balances with the user's own key, same opt-in as OpenRouter.
            let balances: [any UsageProvider] = BalanceDescriptor.all.map {
                BalanceProvider(descriptor: $0, store: AppGroup.keychain())
            }
            let macOnly = MacOptionalProviders.make(source: source)
            providers = [claude, codex] + macOnly + [openRouter, copilot] + balances
        }
        service = UsageService(providers: providers, store: AppGroup.snapshotStore(),
                               history: AppGroup.historyStore())
    }
}

/// Fixed sample data for `-demo` launches (simulator screenshots, UI work without a relay file).
enum DemoProviders {
    struct Demo: UsageProvider {
        let id: String
        let displayName: String
        let plan: String?
        let windows: [(UsageWindow.Kind, Double, TimeInterval, Int)]
        var details: [UsageDetail] = []
        /// How much faster the 5-hour lane fills than the weekly one; high values produce exhausted sessions.
        var sessionGain = 6.0

        func fetchUsage() async throws -> UsageInfo {
            let now = Date()
            let lanes = windows.map { UsageWindow(kind: $0.0, usedPercent: $0.1,
                                                  windowMinutes: $0.3, resetsAt: now.addingTimeInterval($0.2)) }
            return UsageInfo(providerID: id, providerName: displayName, windows: lanes, plan: plan,
                             lastUpdated: now, details: details,
                             history: DemoProviders.history(providerID: id, lanes: lanes, sessionGain: sessionGain, now: now))
        }
    }

    static let all: [any UsageProvider] = [
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

    /// Plausible readings every 20 minutes since the weekly window began: work-hour bursts that end at the
    /// current weekly value, with 5-hour sessions that fill `sessionGain` times faster (and may run out).
    static func history(providerID: String, lanes: [UsageWindow], sessionGain: Double, now: Date) -> [HistorySeries] {
        guard let weekly = lanes.first(where: { $0.kind == .weekly }), let weeklyReset = weekly.resetsAt,
              let minutes = weekly.windowMinutes else { return [] }
        let start = max(weeklyReset.addingTimeInterval(-TimeInterval(minutes) * 60), now.addingTimeInterval(-7 * 86400))
        let calendar = Calendar.current
        let step: TimeInterval = 20 * 60
        var times: [Date] = []
        var t = start
        while t < now { times.append(t); t += step }
        func activity(_ date: Date) -> Double {
            let hour = calendar.component(.hour, from: date)
            let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
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
