import Foundation
import Testing
@testable import AImanaCore

@Suite struct WatchPayloadTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(_ id: String, session: Double, weekly: Double, extraLanes: Int = 0,
                       updated: Date? = nil) -> UsageInfo {
        var windows = [
            UsageWindow(kind: .session, usedPercent: session, windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(2 * 3600 + 0.4)),
            UsageWindow(kind: .weekly, usedPercent: weekly, windowMinutes: 10080,
                        resetsAt: now.addingTimeInterval(3 * 86400)),
        ]
        for i in 0..<extraLanes {
            windows.append(UsageWindow(kind: .model("Model \(i)"), usedPercent: 10, windowMinutes: 10080,
                                       resetsAt: now.addingTimeInterval(86400)))
        }
        let history = [HistorySeries](repeating: HistorySeries(
            providerID: id, kind: .session,
            points: (0..<400).map { HistoryPoint(t: now.addingTimeInterval(Double(-$0) * 300), used: 42, resetsAt: nil) }
        ), count: 2)
        return UsageInfo(providerID: id, providerName: id == "claude" ? "Claude Code" : "OpenAI Codex",
                         windows: windows, plan: "max", lastUpdated: updated ?? now.addingTimeInterval(-120),
                         history: history)
    }

    private func states(claude: Double = 42.37, codex: Double = 12, claudeError: UsageProviderError? = nil)
        -> [ProviderState] {
        [ProviderState(providerID: "claude", displayName: "Claude Code",
                       usage: usage("claude", session: claude, weekly: 61), error: claudeError),
         ProviderState(providerID: "codex", displayName: "OpenAI Codex",
                       usage: usage("codex", session: codex, weekly: 30, extraLanes: 3), error: nil)]
    }

    @Test func roundTripsAndStaysSmall() throws {
        let payload = WatchPayload(states: states(), mode: .remaining, now: now)
        let data = try payload.encoded()
        // Full UsageInfo with history is tens of KB; the watch gets only the lanes.
        #expect(data.count < 1024, "payload is \(data.count) bytes")
        let decoded = try #require(WatchPayload.decode(data))
        #expect(decoded == payload)
        #expect(decoded.mode == .remaining)
        #expect(decoded.providers.map(\.id) == ["claude", "codex"])
        #expect(decoded.providers[0].session?.usedPercent == 42.4)
        #expect(decoded.providers[0].updatedAt == now.addingTimeInterval(-120))
        // Session and weekly first, capped per provider.
        #expect(decoded.providers[1].lanes.count == WatchPayload.maxLanesPerProvider)
        #expect(decoded.providers[1].lanes.prefix(2).map(\.kind) == [.session, .weekly])
        #expect(WatchPayload.from(message: try payload.message()) == payload)
    }

    @Test func worstCaseSizeStaysUnderFourKilobytes() throws {
        let many = (0..<8).map { i in
            ProviderState(providerID: "provider-\(i)", displayName: "Provider number \(i)",
                          usage: usage("provider-\(i)", session: 33.33, weekly: 66.66, extraLanes: 6), error: nil)
        }
        let data = try WatchPayload(states: many, mode: .used, now: now).encoded()
        #expect(data.count < 4096, "payload is \(data.count) bytes")
    }

    @Test func marksIssuesAndDropsEmptyProviders() {
        let input = [
            ProviderState(providerID: "claude", displayName: "Claude Code", usage: nil, error: .unauthenticated),
            ProviderState(providerID: "codex", displayName: "OpenAI Codex",
                          usage: usage("codex", session: 10, weekly: 20), error: .network),
            ProviderState(providerID: "other", displayName: "Other", usage: nil, error: .network),
        ]
        let payload = WatchPayload(states: input, mode: .used, now: now)
        #expect(payload.providers.map(\.id) == ["claude", "codex"])
        #expect(payload.providers[0].issue == .signIn)
        #expect(payload.providers[0].lanes.isEmpty)
        #expect(payload.providers[1].issue == .stale)
        #expect(payload.busiest?.id == "codex")
    }

    @Test func ignoresNewerVersionsAndGarbage() throws {
        #expect(WatchPayload.decode(Data("nope".utf8)) == nil)
        let future = Data(#"{"v":99,"s":0,"d":"used","p":[]}"#.utf8)
        #expect(WatchPayload.decode(future) == nil)
        #expect(WatchPayload.from(message: ["other": 1]) == nil)
    }

    @Test func complicationBudget() {
        let base = WatchPayload(states: states(claude: 42), mode: .used, now: now)
        #expect(base.isMeaningfulChange(from: nil, remainingTransfers: 50))
        #expect(!base.isMeaningfulChange(from: nil, remainingTransfers: 0))
        // Small drift: not worth a transfer.
        let drift = WatchPayload(states: states(claude: 44), mode: .used, now: now)
        #expect(!drift.isMeaningfulChange(from: base, remainingTransfers: 50))
        // Five points: worth one while the budget is healthy, not from the reserve.
        let shift = WatchPayload(states: states(claude: 48), mode: .used, now: now)
        #expect(shift.isMeaningfulChange(from: base, remainingTransfers: 50))
        #expect(!shift.isMeaningfulChange(from: base, remainingTransfers: 5))
        // Severity change (now under 20 % left): always, even from the reserve.
        let warning = WatchPayload(states: states(claude: 85), mode: .used, now: now)
        #expect(warning.isMeaningfulChange(from: shift, remainingTransfers: 2))
        // Sign-in lost.
        let signedOut = WatchPayload(states: states(claude: 42, claudeError: .unauthenticated), mode: .used, now: now)
        #expect(signedOut.isMeaningfulChange(from: base, remainingTransfers: 2))
        // Mode change.
        #expect(WatchPayload(states: states(claude: 42), mode: .remaining, now: now)
            .isMeaningfulChange(from: base, remainingTransfers: 2))
    }

    @Test func storeKeepsTheNewestPayload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WatchPayloadStore(fileURL: url)
        #expect(store.load() == nil)
        let newer = WatchPayload(states: states(claude: 50), mode: .used, now: now)
        let older = WatchPayload(states: states(claude: 10), mode: .used, now: now.addingTimeInterval(-60))
        #expect(try store.save(newer))
        #expect(try !store.save(older))
        #expect(store.load() == newer)
    }

    @Test func balanceOnlyProvidersAreLeftOut() {
        let balance = UsageInfo(providerID: "deepseek", providerName: "DeepSeek", windows: [], plan: nil,
                                lastUpdated: Date(timeIntervalSince1970: 1_000))
        let quota = UsageInfo(providerID: "codex", providerName: "OpenAI Codex",
                              windows: [UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: nil)],
                              plan: nil, lastUpdated: Date(timeIntervalSince1970: 1_000))
        let payload = WatchPayload(snapshot: [balance, quota], mode: .used, now: Date(timeIntervalSince1970: 2_000))
        #expect(payload.providers.map(\.id) == ["codex"])
    }

    @Test func busiestSkipsLanesThatAlreadyReset() {
        let now = Date(timeIntervalSince1970: 10_000)
        let claude = UsageInfo(providerID: "claude", providerName: "Claude Code",
                               windows: [UsageWindow(kind: .session, usedPercent: 100, windowMinutes: 300,
                                                     resetsAt: now.addingTimeInterval(-60))],
                               plan: nil, lastUpdated: now.addingTimeInterval(-3_600))
        let codex = UsageInfo(providerID: "codex", providerName: "OpenAI Codex",
                              windows: [UsageWindow(kind: .session, usedPercent: 40, windowMinutes: 300,
                                                    resetsAt: now.addingTimeInterval(3_600))],
                              plan: nil, lastUpdated: now)
        let payload = WatchPayload(snapshot: [claude, codex], mode: .used, now: now)
        #expect(payload.busiest(at: now)?.id == "codex")
        // Before Claude's reset, its 100 % is current and wins.
        #expect(payload.busiest(at: now.addingTimeInterval(-120))?.id == "claude")
    }
}
