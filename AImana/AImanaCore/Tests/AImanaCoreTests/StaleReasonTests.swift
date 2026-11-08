import Foundation
import Testing
@testable import AImanaCore

private struct FixedData: RelayDataSource {
    let data: Data
    func readData() async throws -> Data { data }
}

private let staleNow = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(minutes: Double) -> Date { staleNow.addingTimeInterval(-minutes * 60) }

/// Same rules as the Kotlin `staleReason` (StaleReasonTest.kt).
@Suite struct StaleReasonTests {
    private func reading(published: Date, updated: Date, source: RelaySource?) async throws -> UsageInfo {
        let usage = UsageInfo(providerID: "claude", providerName: "Claude Code",
                              windows: [UsageWindow(kind: .session, usedPercent: 40, windowMinutes: 300, resetsAt: nil)],
                              plan: nil, lastUpdated: updated)
        let data = try RelayEnvelope(generatedAt: published,
                                     entries: [RelayEntry(providerID: "claude", usage: usage, error: nil, source: source)]).encoded()
        return try await RelayProvider(id: "claude", displayName: "Claude Code", source: FixedData(data: data)).fetchUsage()
    }

    @Test func relayReadingsKnowWhenTheComputerPublished() async throws {
        let info = try await reading(published: ago(minutes: 5), updated: ago(minutes: 90), source: .logs)
        #expect(info.relayPublishedAt == ago(minutes: 5))
        // It survives the snapshot the widgets read, and the extras the service adds.
        let saved = try JSONDecoder().decode(UsageInfo.self, from: try JSONEncoder().encode(info.withExtras(cost: nil, history: [])))
        #expect(saved.relayPublishedAt == ago(minutes: 5))
    }

    @Test func freshReadingHasNoReason() async throws {
        #expect(StaleReason(info: try await reading(published: ago(minutes: 5), updated: ago(minutes: 30), source: .endpoint), now: staleNow) == nil)
    }

    @Test func computerThatStoppedPublishingIsTheReason() async throws {
        let silent = try await reading(published: ago(minutes: 180), updated: ago(minutes: 180), source: .endpoint)
        #expect(StaleReason(info: silent, now: staleNow) == .publisherSilent(since: ago(minutes: 180)))
        let logs = try await reading(published: ago(minutes: 120), updated: ago(minutes: 300), source: .logs)
        #expect(StaleReason(info: logs, now: staleNow) == .publisherSilent(since: ago(minutes: 120)))
    }

    @Test func localSourcesWaitForTheNextUse() async throws {
        #expect(StaleReason(info: try await reading(published: ago(minutes: 5), updated: ago(minutes: 240), source: .statusline), now: staleNow) == .noRecentUse)
        #expect(StaleReason(info: try await reading(published: ago(minutes: 5), updated: ago(minutes: 240), source: .logs), now: staleNow) == .noRecentUse)
    }

    @Test func unknownCausesStayGeneric() async throws {
        #expect(StaleReason(info: try await reading(published: ago(minutes: 5), updated: ago(minutes: 240), source: .endpoint), now: staleNow) == nil)
        let direct = UsageInfo(providerID: "claude", providerName: "Claude Code", windows: [], plan: nil, lastUpdated: ago(minutes: 240))
        #expect(StaleReason(info: direct, now: staleNow) == nil)
    }
}
