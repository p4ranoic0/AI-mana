import Foundation
import Testing
@testable import AImanaCore

/// The pieces the Mac app adds on top of the shared planner: its own storage and its own sign-in wording.
@Suite struct MacNotificationTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let en = Locale(identifier: "en")

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macnotif-\(UUID().uuidString)/file.json")
    }

    @Test func preferencesFileDefaultsToOffAndRoundTrips() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = NotificationPreferencesFile(url: url)
        #expect(file.load() == NotificationPreferences())
        #expect(file.load().isEnabled == false)

        var prefs = NotificationPreferences(isEnabled: true, paceAlerts: false, dailySummary: true, summaryMinutes: 9 * 60)
        prefs.setWindow(WindowAlertSettings(thresholds: [50, 90]), providerID: "codex", lane: .weekly)
        file.save(prefs)
        #expect(file.load() == prefs)
        #expect(file.load().window(providerID: "codex", lane: .weekly).thresholds == [50, 90])
    }

    @Test func stateFileWithoutLegacyFallbackStartsEmpty() {
        let url = tempURL()
        let file = NotificationStateFile(url: url, legacyFallback: false)
        #expect(file.load() == NotificationState())
    }

    @Test func relayEntryBecomesProviderState() {
        let window = UsageWindow(kind: .session, usedPercent: 42, windowMinutes: 300, resetsAt: t0.addingTimeInterval(3600))
        let usage = UsageInfo(providerID: "claude", providerName: "Claude Code", windows: [window], plan: nil, lastUpdated: t0)
        let ok = ProviderState(relayEntry: RelayEntry(providerID: "claude", usage: usage, error: nil, source: .statusline))
        #expect(ok.displayName == "Claude Code")
        #expect(ok.usage == usage)
        #expect(ok.error == nil)

        let failed = ProviderState(relayEntry: RelayEntry(providerID: "codex", usage: nil, error: .unauthenticated))
        #expect(failed.displayName == "OpenAI Codex")
        #expect(failed.error == .unauthenticated)
    }

    @Test func thisMacOriginTalksAboutThisMacNotTheIPhone() throws {
        let plan = NotificationPlanner.plan(state: NotificationState(), states: [], logins: ["claude": .expired],
                                            loginOrigin: .thisMac, preferences: NotificationPreferences(isEnabled: true),
                                            now: t0, locale: en)
        let alert = try #require(plan.deliver.first)
        #expect(alert.kind == .loginExpired)
        #expect(alert.title == "AI·mana for Mac lost access to claude")
        #expect(alert.body.contains("this Mac"))
        #expect(!alert.body.contains("iPhone"))
        #expect(plan.state.loginNotified == ["claude"])

        // Announced once until the access works again.
        let again = NotificationPlanner.plan(state: plan.state, states: [], logins: ["claude": .expired],
                                             loginOrigin: .thisMac, preferences: NotificationPreferences(isEnabled: true),
                                             now: t0, locale: en)
        #expect(again.deliver.isEmpty)
        let cleared = NotificationPlanner.plan(state: plan.state, states: [], logins: ["claude": .signedOut],
                                               loginOrigin: .thisMac, preferences: NotificationPreferences(isEnabled: true),
                                               now: t0, locale: en)
        #expect(cleared.state.loginNotified.isEmpty)
    }

    @Test func settingsSourceIsInjectable() {
        let prefs = NotificationPreferences(isEnabled: true)
        let source = NotificationSettingsSource(preferences: { prefs })
        #expect(source.preferences() == prefs)
        #expect(source.displayMode() == .used)
        #expect(source.savedUsages().isEmpty)
    }
}
