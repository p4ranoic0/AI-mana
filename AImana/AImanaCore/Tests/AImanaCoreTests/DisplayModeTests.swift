import Foundation
import Testing
@testable import AImanaCore

@Suite struct DisplayModeTests {
    private let window = UsageWindow(kind: .session, usedPercent: 18, windowMinutes: 300, resetsAt: nil)

    @Test func percentFollowsMode() {
        #expect(DisplayMode.used.percent(for: window) == 18)
        #expect(DisplayMode.remaining.percent(for: window) == 82)
    }

    @Test func overQuotaStaysInRange() {
        let over = UsageWindow(kind: .session, usedPercent: 140, windowMinutes: nil, resetsAt: nil)
        #expect(DisplayMode.used.percent(for: over) == 100)
        #expect(DisplayMode.remaining.percent(for: over) == 0)
    }

    @Test func defaultsToUsedAndPersists() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        #expect(DisplayPreferences.mode(defaults: defaults) == .used)
        DisplayPreferences.setMode(.remaining, defaults: defaults)
        #expect(DisplayPreferences.mode(defaults: defaults) == .remaining)
    }

    @Test func unknownStoredValueFallsBackToUsed() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("bogus", forKey: DisplayPreferences.modeKey)
        #expect(DisplayPreferences.mode(defaults: defaults) == .used)
    }

    @Test func styleDefaultsToBarsAndPersists() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        #expect(DisplayPreferences.style(defaults: defaults) == .bars)
        DisplayPreferences.setStyle(.rings, defaults: defaults)
        #expect(DisplayPreferences.style(defaults: defaults) == .rings)
        DisplayPreferences.setStyle(.numbers, defaults: defaults)
        #expect(DisplayPreferences.style(defaults: defaults) == .numbers)
    }

    @Test func unknownStyleFallsBackToBarsWithoutChangingMode() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        DisplayPreferences.setMode(.remaining, defaults: defaults)
        defaults.set("unknown", forKey: DisplayPreferences.styleKey)
        #expect(DisplayPreferences.style(defaults: defaults) == .bars)
        #expect(DisplayPreferences.mode(defaults: defaults) == .remaining)
        #expect(DisplayStyle.allCases.map { $0.title(locale: Locale(identifier: "en_US")) } == ["Bars", "Rings", "Numbers"])
    }

    @Test func severityAlwaysFollowsRemaining() {
        #expect(UsageSeverity(remainingPercent: 50) == .normal)
        #expect(UsageSeverity(remainingPercent: 19) == .warning)
        #expect(UsageSeverity(remainingPercent: 9) == .critical)
        #expect(UsageSeverity(remainingPercent: 0) == .critical)
    }
}
