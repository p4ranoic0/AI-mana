import Foundation

/// Notification preferences kept in a plain JSON file, for a process outside the App Group (the Mac app). Missing or
/// unreadable files mean the defaults: alerts off until the user opts in.
public struct NotificationPreferencesFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> NotificationPreferences {
        guard let data = try? Data(contentsOf: url) else { return NotificationPreferences() }
        return (try? JSONDecoder().decode(NotificationPreferences.self, from: data)) ?? NotificationPreferences()
    }

    public func save(_ preferences: NotificationPreferences) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}

extension ProviderState {
    /// A published relay entry as the planner sees it.
    public init(relayEntry entry: RelayEntry) {
        let fallback = switch entry.providerID {
        case "claude": "Claude Code"
        case "codex": "OpenAI Codex"
        default: entry.providerID
        }
        let name = entry.usage?.providerName ?? fallback
        self.init(providerID: entry.providerID, displayName: name, usage: entry.usage,
                  error: entry.error?.providerError)
    }
}
