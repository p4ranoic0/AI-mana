import Foundation

/// Why an old relay reading is old, when it can be told: the computer stopped publishing, or the CLI was not used
/// since. Same rules as the Kotlin `staleReason`.
public enum StaleReason: Equatable, Sendable {
    case publisherSilent(since: Date)
    case noRecentUse

    /// Readings younger than this are current (the cards' "outdated" mark uses the same hour).
    static let age: TimeInterval = 3600

    public init?(info: UsageInfo, now: Date = Date()) {
        guard now.timeIntervalSince(info.lastUpdated) > Self.age, let published = info.relayPublishedAt else { return nil }
        if now.timeIntervalSince(published) > Self.age {
            self = .publisherSilent(since: published)
        } else if info.source == .statusline || info.source == .logs {
            // Endpoint readings refresh on every publish; these only change when the CLI writes something new.
            self = .noRecentUse
        } else {
            return nil
        }
    }
}
