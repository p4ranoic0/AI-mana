import Foundation
import Testing
@testable import AImanaCore

@Suite struct CostModelTests {
    private func day(_ d: String, usd: Double, tokens: Int = 1000, unpriced: Int = 0) -> DailyCost {
        DailyCost(day: d, tokens: TokenUsage(input: tokens, output: 0, cacheRead: 0, cacheWrite: 0),
                  usd: usd, unpricedTokens: unpriced, models: [])
    }

    @Test func tokenUsageSumsAndTotals() {
        let a = TokenUsage(input: 10, output: 5, cacheRead: 100, cacheWrite: 20)
        let b = TokenUsage(input: 1, output: 2, cacheRead: 3, cacheWrite: 4)
        let sum = a + b
        #expect(sum == TokenUsage(input: 11, output: 7, cacheRead: 103, cacheWrite: 24))
        #expect(sum.total == 145)
    }

    @Test func totalsForRecentDays() {
        let report = CostReport(providerID: "claude", generatedAt: Date(), days: [
            day("2026-10-01", usd: 10), day("2026-10-02", usd: 20), day("2026-10-03", usd: 30), day("2026-10-04", usd: 40),
        ])
        #expect(report.total(lastDays: 1, endingOn: "2026-10-04").usd == 40)
        #expect(report.total(lastDays: 2, endingOn: "2026-10-04").usd == 70)
        #expect(report.total(lastDays: 30, endingOn: "2026-10-04").usd == 100)
        // A window that ends before the data starts is empty.
        #expect(report.total(lastDays: 3, endingOn: "2026-09-20").usd == 0)
    }

    @Test func totalsFlagUnpricedTokens() {
        let report = CostReport(providerID: "codex", generatedAt: Date(),
                                days: [day("2026-10-04", usd: 5, unpriced: 123)])
        let total = report.total(lastDays: 7, endingOn: "2026-10-04")
        #expect(total.unpricedTokens == 123)
    }

    @Test func envelopeCarriesCostsAndHistoryAndStaysBackwardCompatible() throws {
        let point = HistoryPoint(t: Date(timeIntervalSince1970: 1_800_000_000), used: 12,
                                 resetsAt: Date(timeIntervalSince1970: 1_800_018_000))
        let env = RelayEnvelope(generatedAt: Date(timeIntervalSince1970: 1_800_000_100), entries: [],
                                costs: [CostReport(providerID: "claude", generatedAt: Date(timeIntervalSince1970: 1_800_000_050), days: [day("2026-10-04", usd: 1.5)])],
                                history: [HistorySeries(providerID: "claude", kind: .session, points: [point])])
        #expect(try RelayEnvelope.decode(try env.encoded()) == env)

        // An envelope written by an older relay has neither key.
        let old = #"{"version":1,"generatedAt":"2027-01-15T10:00:00Z","entries":[]}"#
        let decoded = try RelayEnvelope.decode(Data(old.utf8))
        #expect(decoded.costs.isEmpty && decoded.history.isEmpty)
    }

    @Test func relayProviderMergesExtrasIntoUsage() async throws {
        struct Source: RelayDataSource {
            let data: Data
            func readData() async throws -> Data { data }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = UsageInfo(providerID: "claude", providerName: "Claude", windows: [], plan: nil, lastUpdated: now)
        let env = RelayEnvelope(generatedAt: now, entries: [RelayEntry(providerID: "claude", usage: usage, error: nil)],
                                costs: [CostReport(providerID: "claude", generatedAt: now, days: [day("2026-10-04", usd: 9)]),
                                        CostReport(providerID: "codex", generatedAt: now, days: [day("2026-10-04", usd: 99)])],
                                history: [HistorySeries(providerID: "claude", kind: .weekly, points: []),
                                          HistorySeries(providerID: "codex", kind: .weekly, points: [])])
        let info = try await RelayProvider(id: "claude", displayName: "Claude", source: Source(data: try env.encoded())).fetchUsage()
        #expect(info.cost?.days.first?.usd == 9)          // only its own provider's report
        #expect(info.history.count == 1 && info.history[0].providerID == "claude")
    }

    @Test func usageInfoWithoutExtrasDecodes() throws {
        let json = #"{"providerID":"claude","providerName":"Claude","windows":[],"plan":null,"lastUpdated":"2027-01-15T10:00:00Z"}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(UsageInfo.self, from: Data(json.utf8))
        #expect(info.cost == nil && info.history.isEmpty)
    }
}
