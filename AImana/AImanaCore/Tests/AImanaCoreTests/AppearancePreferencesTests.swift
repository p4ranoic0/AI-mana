import Foundation
import Testing
@testable import AImanaCore

@Suite struct AppearancePreferencesTests {
    @Test func defaultsAndPersistence() {
        let defaults = UserDefaults(suiteName: "appearance-test-\(UUID().uuidString)")!
        #expect(AppearancePreferences.theme(defaults: defaults) == .system)
        #expect(AppearancePreferences.accent(defaults: defaults) == .blue)
        AppearancePreferences.setTheme(.dark, defaults: defaults)
        AppearancePreferences.setAccent(.purple, defaults: defaults)
        #expect(AppearancePreferences.theme(defaults: defaults) == .dark)
        #expect(AppearancePreferences.accent(defaults: defaults) == .purple)
    }

    @Test func unknownValuesUseDefaults() {
        let defaults = UserDefaults(suiteName: "appearance-test-\(UUID().uuidString)")!
        defaults.set("unknown", forKey: AppearancePreferences.themeKey)
        defaults.set("unknown", forKey: AppearancePreferences.accentKey)
        #expect(AppearancePreferences.theme(defaults: defaults) == .system)
        #expect(AppearancePreferences.accent(defaults: defaults) == .blue)
    }
}
