import Foundation

enum WidgetStrings {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    static func updated(_ date: Date, relativeTo now: Date) -> String {
        // Under a minute (or a clock slightly ahead on the Mac) reads as "just now", never "in 0 s".
        if now.timeIntervalSince(date) < 60 { return text("Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return format("Updated %@", formatter.localizedString(for: date, relativeTo: now))
    }

    /// Providers with credentials available directly to this widget.
    static var phoneSignInProviderIDs: Set<String> {
        []
    }

    /// "Sign in again" for providers the phone signs in to, "Sign in again on your computer" when every
    /// provider involved is read only from the relay.
    static func signInAgain(for providerIDs: Set<String>) -> String {
        providerIDs.isDisjoint(with: phoneSignInProviderIDs) ? text("Sign in again on your computer") : text("Sign in again")
    }
}
