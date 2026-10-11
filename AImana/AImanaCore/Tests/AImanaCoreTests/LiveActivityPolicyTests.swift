import Foundation
import Testing
@testable import AImanaCore

@Suite struct LiveActivityPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(_ used: Double, reset: Date? = nil) -> UsageInfo {
        UsageInfo(providerID: "claude", providerName: "Claude Code",
                  windows: [UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300,
                                        resetsAt: reset ?? now.addingTimeInterval(3600))],
                  plan: nil, lastUpdated: now)
    }

    @Test func startsOnlyWhenCurrentWindowIncreases() {
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(21),
                                           hasActivity: false, autoStartEnabled: true,
                                           lastChangedAt: nil, now: now) == .start)
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(20),
                                           hasActivity: false, autoStartEnabled: true,
                                           lastChangedAt: nil, now: now) == .none)
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(21),
                                           hasActivity: false, autoStartEnabled: false,
                                           lastChangedAt: nil, now: now) == .none)
        #expect(!LiveActivityPolicy.increased(previous: usage(20, reset: now.addingTimeInterval(7200)),
                                               current: usage(21)))
    }

    @Test func updatesExistingAndEndsAfterIdleOrReset() {
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(21),
                                           hasActivity: true, autoStartEnabled: true,
                                           lastChangedAt: now.addingTimeInterval(-7201), now: now) == .update)
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(20),
                                           hasActivity: true, autoStartEnabled: true,
                                           lastChangedAt: now.addingTimeInterval(-7200), now: now) == .end)
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(20, reset: now),
                                           hasActivity: true, autoStartEnabled: true,
                                           lastChangedAt: now, now: now) == .end)
        #expect(LiveActivityPolicy.action(previous: usage(20), current: nil,
                                           hasActivity: true, autoStartEnabled: true,
                                           lastChangedAt: now, now: now) == .end)
    }

    @Test func manualActivitySurvivesDisabledAutoStart() {
        #expect(LiveActivityPolicy.action(previous: usage(20), current: usage(20),
                                           hasActivity: true, autoStartEnabled: false,
                                           manuallyStarted: true, lastChangedAt: now, now: now) == .update)
    }

    @Test func preferenceDefaultsToOnAndPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LiveActivityPreferences.isEnabled(defaults: defaults))
        LiveActivityPreferences.setEnabled(false, defaults: defaults)
        #expect(!LiveActivityPreferences.isEnabled(defaults: defaults))
    }
}
