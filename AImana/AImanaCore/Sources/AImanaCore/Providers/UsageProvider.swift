import Foundation

public enum UsageProviderError: Error, Sendable, Equatable {
    /// Missing, expired or revoked credentials. Requires user action.
    case unauthenticated
    case rateLimited(until: Date?)
    /// Response shape was not understood.
    case decoding
    /// Transient transport failure.
    case network
    case server(status: Int)
    /// The Mac relay file is missing, unreadable, or has no entry for this provider.
    case relayUnavailable

    /// Errors after which the last known snapshot is still meaningful.
    public var keepsStaleData: Bool {
        switch self {
        case .unauthenticated: false
        case .rateLimited, .decoding, .network, .server, .relayUnavailable: true
        }
    }
}

/// Every usage source implements this. Adding a provider must not require UI changes.
public protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// False while an opt-in provider is not set up (e.g. no OpenRouter key saved): it is then left out of
    /// refreshes and of the dashboard entirely, rather than shown as signed out. Checked on every refresh.
    var isEnabled: Bool { get }
    /// True for opt-in relay providers that should stay off the dashboard until there is data for them: no card
    /// before the first reading, and none once the Mac stops publishing them.
    var hidesWithoutData: Bool { get }
    func fetchUsage() async throws -> UsageInfo
}

public extension UsageProvider {
    var isEnabled: Bool { true }
    var hidesWithoutData: Bool { false }
}
