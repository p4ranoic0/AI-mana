import AImanaCore
import Foundation

/// Shared app-wide services. The widget builds its own over the same Keychain items; `AppGroup` gives both the
/// shared lock that keeps renewals apart.
enum Services {
    /// Device credentials for Codex usage.
    static let codexTokens = AppGroup.codexTokens()
    /// Device credentials for Claude usage.
    static let claudeTokens = AppGroup.claudeTokens()
    /// The user's opt-in to direct access, shared with the widget. Without it the sessions above are never used.
    static let consent = DirectAccessConsent()
}
