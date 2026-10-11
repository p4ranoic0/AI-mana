import Foundation
import Testing
@testable import AImanaCore

@Suite struct WidgetStatusPreferencesTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "widget-status-\(UUID().uuidString)")! }

    private func state(_ id: String, usage: Bool, error: UsageProviderError?) -> ProviderState {
        let info = usage ? UsageInfo(providerID: id, providerName: id,
                                     windows: [UsageWindow(kind: .session, usedPercent: 31, windowMinutes: 300,
                                                           resetsAt: nil)],
                                     plan: nil, lastUpdated: Date()) : nil
        return ProviderState(providerID: id, displayName: id, usage: info, error: error)
    }

    @Test func emptyByDefault() {
        #expect(WidgetStatusPreferences.loginRequiredProviderIDs(defaults: defaults()).isEmpty)
    }

    @Test func legacyTrueFlagNamesNoProvider() {
        let defaults = defaults()
        defaults.set(true, forKey: WidgetStatusPreferences.legacyLoginKey)
        #expect(WidgetStatusPreferences.loginRequiredProviderIDs(defaults: defaults).isEmpty)
        #expect(!WidgetStatusPreferences.loginRequired(for: "claude", defaults: defaults))
    }

    @Test func onlyTheUnauthenticatedProviderIsRecorded() {
        let defaults = defaults()
        WidgetStatusPreferences.update(from: [
            state("claude", usage: true, error: nil),
            state("codex", usage: true, error: nil),
            state("extra", usage: false, error: .unauthenticated),
            state("copilot", usage: false, error: .network),
        ], defaults: defaults)
        #expect(WidgetStatusPreferences.loginRequiredProviderIDs(defaults: defaults) == ["extra"])
        #expect(WidgetStatusPreferences.loginRequired(for: "extra", defaults: defaults))
        #expect(!WidgetStatusPreferences.loginRequired(for: "claude", defaults: defaults))
        #expect(!WidgetStatusPreferences.loginRequired(for: "codex", defaults: defaults))
        #expect(defaults.object(forKey: WidgetStatusPreferences.legacyLoginKey) == nil)
    }

    @Test func staleDataWithExpiredSignInStillCounts() {
        let ids = WidgetStatusPreferences.providersNeedingSignIn([state("codex", usage: true, error: .unauthenticated)])
        #expect(ids == ["codex"])
    }

    @Test func aCleanRefreshClearsTheSet() {
        let defaults = defaults()
        WidgetStatusPreferences.setLoginRequiredProviderIDs(["claude", "extra"], defaults: defaults)
        #expect(WidgetStatusPreferences.loginRequiredProviderIDs(defaults: defaults) == ["claude", "extra"])
        WidgetStatusPreferences.update(from: [state("claude", usage: true, error: nil)], defaults: defaults)
        #expect(WidgetStatusPreferences.loginRequiredProviderIDs(defaults: defaults).isEmpty)
    }
}
