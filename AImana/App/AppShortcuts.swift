import AppIntents

/// Siri phrases. Every phrase names the app; Spanish and the other languages come from the AppShortcuts string
/// catalog (keys use `${applicationName}` and `${provider}`).
struct AImanaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetUsageIntent(), phrases: [
            "How much is left in \(.applicationName)?",
            "Get usage from \(.applicationName)",
            "\(\.$provider) usage in \(.applicationName)",
            "How much \(\.$provider) is left in \(.applicationName)?",
        ], shortTitle: "Usage", systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(intent: RefreshUsageIntent(), phrases: [
            "Refresh \(.applicationName)",
            "Refresh usage in \(.applicationName)",
        ], shortTitle: "Refresh Usage", systemImageName: "arrow.clockwise")
    }
}
