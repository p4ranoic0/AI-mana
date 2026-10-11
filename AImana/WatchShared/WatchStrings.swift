import AImanaCore
import Foundation

/// Copy owned by the watch app and its complications (each target bundles `Localizable.xcstrings`).
enum WatchStrings {
    static var signInLocation: String {
        text("Check AImana for Mac")
    }

    static var shortSignInLocation: String {
        text("Check AImana for Mac")
    }

    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    /// "3 hr. ago" / "hace 3 h". Under a minute (or a clock slightly ahead) reads as "just now".
    static func age(of date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return text("just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "Updated 4 min ago" / "Updated just now".
    static func updated(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return text("Updated just now") }
        return format("Updated %@", age(of: date, now: now))
    }
}

/// Freshness rules shared by the app screen and the complications.
enum WatchFreshness {
    /// Same rule as the iPhone widgets: a reading older than an hour is flagged, never shown as current.
    static let staleAfter: TimeInterval = 3600

    static func isStale(_ provider: WatchPayload.Provider, now: Date) -> Bool {
        guard let updated = provider.updatedAt else { return true }
        return now.timeIntervalSince(updated) > staleAfter || provider.issue != nil
            || provider.lanes.contains { $0.window.isOutdated(now: now) }
    }
}

#if DEBUG
/// Sample data for the simulator (`-AImanaWatchSample fresh|stale|signin`) and previews. Never shipped.
enum WatchSample {
    static let launchArgument = "AImanaWatchSample"

    static var requested: String? {
        UserDefaults.standard.string(forKey: launchArgument)
    }

    static func payload(_ variant: String = "fresh", now: Date = Date()) -> WatchPayload {
        let age: TimeInterval = variant == "stale" ? 3 * 3600 + 600 : 4 * 60
        let claude = WatchPayload.Provider(
            id: "claude", name: "Claude Code", updatedAt: now.addingTimeInterval(-age),
            lanes: [
                .init(kind: .session, used: 42, minutes: 300, resetsAt: now.addingTimeInterval(2 * 3600 + 600)),
                .init(kind: .weekly, used: 61, minutes: 10080, resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600)),
            ],
            issue: variant == "signin" ? .signIn : nil)
        let codex = WatchPayload.Provider(
            id: "codex", name: "OpenAI Codex", updatedAt: now.addingTimeInterval(-age - 120),
            lanes: [
                .init(kind: .session, used: 83, minutes: 300, resetsAt: now.addingTimeInterval(3 * 3600 + 1200)),
                .init(kind: .weekly, used: 30, minutes: 10080, resetsAt: now.addingTimeInterval(5 * 86400)),
            ],
            issue: nil)
        return WatchPayload(sentAt: now.addingTimeInterval(-age + 5), mode: .used, providers: [claude, codex])
    }
}
#endif
