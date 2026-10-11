import Foundation
import Testing
@testable import AImanaCore

private struct FixedData: RelayDataSource {
    let data: Data
    func readData() async throws -> Data { data }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func usage(_ id: String) -> UsageInfo {
    UsageInfo(providerID: id, providerName: id,
              windows: [UsageWindow(kind: .session, usedPercent: 12, windowMinutes: 300, resetsAt: t0.addingTimeInterval(3600))],
              plan: nil, lastUpdated: t0)
}

/// `RelayEntry.source` travels from the envelope to the `UsageInfo` the UI shows, and survives the snapshot.
@Suite struct RelaySourcePlumbingTests {
    private func fetch(_ entries: [RelayEntry], id: String) async throws -> UsageInfo {
        let data = try RelayEnvelope(generatedAt: t0, entries: entries).encoded()
        return try await RelayProvider(id: id, displayName: id, source: FixedData(data: data)).fetchUsage()
    }

    @Test func providerCarriesEntrySource() async throws {
        let entries = [RelayEntry(providerID: "claude", usage: usage("claude"), error: nil, source: .statusline),
                       RelayEntry(providerID: "codex", usage: usage("codex"), error: nil, source: .logs)]
        #expect(try await fetch(entries, id: "claude").source == .statusline)
        #expect(try await fetch(entries, id: "codex").source == .logs)
    }

    @Test func missingSourceStaysNil() async throws {
        let info = try await fetch([RelayEntry(providerID: "claude", usage: usage("claude"), error: nil)], id: "claude")
        #expect(info.source == nil)
    }

    @Test func envelopeUsageHasNoSourceKey() throws {
        // The source lives on the entry; the usage payload the Mac writes keeps its old shape.
        let data = try RelayEnvelope(generatedAt: t0, entries: [
            RelayEntry(providerID: "claude", usage: usage("claude"), error: nil, source: .endpoint),
        ]).encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try #require((json["entries"] as? [[String: Any]])?.first)
        #expect(entry["source"] as? String == "endpoint")
        let usageJSON = try #require(entry["usage"] as? [String: Any])
        #expect(usageJSON["source"] == nil)
    }

    @Test func sourceSurvivesSnapshotAndExtras() throws {
        let tagged = usage("codex").withSource(.endpoint).withExtras(cost: nil, history: [])
        #expect(tagged.source == .endpoint)
        let decoded = try JSONDecoder().decode(UsageInfo.self, from: try JSONEncoder().encode(tagged))
        #expect(decoded == tagged)
    }

    @Test func unknownSourceInSnapshotDecodesAsNil() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(usage("claude")))
            as? [String: Any])
        json["source"] = "carrier-pigeon"
        let decoded = try JSONDecoder().decode(UsageInfo.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(decoded.source == nil)
        #expect(decoded.providerID == "claude")
    }

    @Test func hybridDirectReadingHasNoMacSource() async throws {
        struct Fixed: UsageProvider {
            let id = "claude", displayName = "Claude Code"
            let info: UsageInfo
            func fetchUsage() async throws -> UsageInfo { info }
        }
        let hybrid = HybridProvider(direct: Fixed(info: usage("claude")),
                                    relay: Fixed(info: usage("claude").withSource(.statusline)),
                                    isDirectEnabled: { true })
        #expect(try await hybrid.fetchUsage().source == nil)
        let relayOnly = HybridProvider(direct: Fixed(info: usage("claude")),
                                       relay: Fixed(info: usage("claude").withSource(.statusline)),
                                       isDirectEnabled: { false })
        #expect(try await relayOnly.fetchUsage().source == .statusline)
    }
}

/// Builds without phone sign-ins announce lost access as the Mac's, judged from what the relay reports.
@Suite struct MacLoginAlertTests {
    private let en = Locale(identifier: "en")

    private func state(_ id: String, error: UsageProviderError?, usage hasUsage: Bool = true) -> ProviderState {
        ProviderState(providerID: id, displayName: id == "claude" ? "Claude Code" : "OpenAI Codex",
                      usage: hasUsage ? usage(id) : nil, error: error)
    }

    #if canImport(UserNotifications)
    @Test func relayStatusMapsToLoginStatus() {
        let logins = NotificationDelivery.macLogins([
            state("claude", error: .unauthenticated, usage: false),
            state("codex", error: nil),
        ], providerIDs: ["claude", "codex"])
        #expect(logins == ["claude": .expired, "codex": .active])

        // Relay unreachable or network trouble says nothing about the Mac's access.
        let unknown = NotificationDelivery.macLogins([
            state("claude", error: .relayUnavailable, usage: false),
            state("codex", error: .network),
        ], providerIDs: ["claude", "codex"])
        #expect(unknown.isEmpty)
    }
    #endif

    @Test func macOriginAlertNamesTheMacAndTheTool() {
        let plan = NotificationPlanner.plan(state: NotificationState(),
                                            states: [state("codex", error: .unauthenticated, usage: false)],
                                            logins: ["codex": .expired], loginOrigin: .mac,
                                            preferences: NotificationPreferences(isEnabled: true), now: t0, locale: en)
        let alert = try? #require(plan.deliver.first)
        #expect(alert?.kind == .loginExpired)
        #expect(alert?.title == "AI·mana for Mac lost access to OpenAI Codex")
        #expect(alert?.body.contains("on your Mac") == true)
        #expect(plan.state.loginNotified == ["codex"])
    }

    /// Mixed relay and device origins identify the correct place to restore access.
    @Test func mixedOriginsNameTheRightPlace() {
        let plan = NotificationPlanner.plan(state: NotificationState(),
                                            states: [state("claude", error: .unauthenticated, usage: false),
                                                     state("codex", error: .unauthenticated, usage: false)],
                                            logins: ["claude": .expired, "codex": .expired],
                                            macLoginProviderIDs: ["claude"],
                                            preferences: NotificationPreferences(isEnabled: true), now: t0, locale: en)
        let titles = plan.deliver.map(\.title)
        #expect(titles.contains("AI·mana for Mac lost access to Claude Code"))
        #expect(titles.contains("ChatGPT sign-in expired"))
        #expect(plan.state.loginNotified == ["claude", "codex"])
    }

    @Test func macAlertRespectsToggle() {
        let prefs = NotificationPreferences(isEnabled: true, loginAlerts: false)
        let plan = NotificationPlanner.plan(state: NotificationState(), states: [], logins: ["claude": .expired],
                                            loginOrigin: .mac, preferences: prefs, now: t0, locale: en)
        #expect(plan.deliver.isEmpty)
    }
}
