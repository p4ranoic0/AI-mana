import AImanaCore
import Foundation

enum AppStrings {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    static func updated(_ date: Date, relativeTo now: Date = .now) -> String {
        // Under a minute (or a clock slightly ahead on the Mac) reads as "just now", never "in 0 s".
        if now.timeIntervalSince(date) < 60 { return text("Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return format("Updated %@", formatter.localizedString(for: date, relativeTo: now))
    }
}

extension RelaySource {
    /// Where the Mac got a provider's numbers, as a short caption for detail and Settings.
    var caption: String {
        switch self {
        case .statusline: AppStrings.text("From Claude Code on your Mac")
        case .logs: AppStrings.text("From Codex logs on your Mac")
        case .endpoint: ""
        }
    }
}
