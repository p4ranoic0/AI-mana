import AImanaCore
#if SWIFT_PACKAGE
import AImanaSignIn
#endif
import Foundation
import RelayKit

/// Claude and Codex usage read straight from each provider with the session its CLI already keeps on this computer.
/// Callers request it only after the user's consent (`DirectAccessConsent`); the factory itself never decides.
public enum DirectEndpoints {
    /// `defaults` keeps each endpoint's 429 block across publishes: the publisher builds new providers every time.
    /// `isAllowed` is asked again on every fetch, before and after the request: a consent withdrawn while a publish
    /// is running stops that provider at once instead of when the publish ends.
    public static func factory(paths: RelayPaths = .standard, defaults: UserDefaults = .standard,
                               log: @escaping @Sendable (String) -> Void,
                               isAllowed: @escaping @Sendable (String) -> Bool = { _ in true }) -> RelayPublisher.EndpointFactory {
        let claudeGate = BackoffGate.shared("claude", defaults: defaults)
        let codexGate = BackoffGate.shared("codex", defaults: defaults)
        return { id, options in
            let provider: (any UsageProvider)? = switch id {
            case "claude": ClaudeProvider(tokens: claudeTokens(options: options, paths: paths, log: log), gate: claudeGate)
            case "codex": CodexProvider(tokens: CodexAuthFileTokens(paths: paths), gate: codexGate)
            default: nil
            }
            return provider.map { ConsentGated($0, isAllowed: { isAllowed(id) }) }
        }
    }

    static func claudeTokens(options: RelayOptions, paths: RelayPaths = .standard,
                             log: @escaping @Sendable (String) -> Void) -> ClaudeCLITokens {
        ClaudeCLITokens(renew: options.renewClaude, paths: paths, log: log)
    }
}

/// A direct provider that runs only while the user's consent holds: checked before credentials are read and again
/// when the answer arrives, so a withdrawn consent never publishes a reading. Refusals look like "no endpoint data",
/// which makes the publisher use the local sources.
public struct ConsentGated: UsageProvider {
    private let inner: any UsageProvider
    private let isAllowed: @Sendable () -> Bool
    public var id: String { inner.id }
    public var displayName: String { inner.displayName }

    public init(_ inner: any UsageProvider, isAllowed: @escaping @Sendable () -> Bool) {
        self.inner = inner
        self.isAllowed = isAllowed
    }

    public func fetchUsage() async throws -> UsageInfo {
        guard isAllowed() else { throw UsageProviderError.relayUnavailable }
        let usage = try await inner.fetchUsage()
        guard isAllowed() else { throw UsageProviderError.relayUnavailable }
        return usage
    }
}

/// The Mac's direct-access choices turned into publish options. A provider's endpoint is used only when its toggle is
/// on **and** the user's consent is current; the toggle alone (e.g. from an earlier build) is not enough.
public enum MacDirectOptions {
    public static let providers: [DirectProvider] = [.claude, .codex]

    public static func active(enabled: [String: Bool], consent: DirectAccessConsent) -> Set<String> {
        Set(providers.filter { enabled[$0.rawValue] == true && consent.isGranted($0) }.map(\.rawValue))
    }

    public static func make(output: URL, enabled: [String: Bool], consent: DirectAccessConsent,
                            optionalProviderIDs: [String] = [], refreshOptional: Bool = true) -> RelayOptions {
        let ids = active(enabled: enabled, consent: consent)
        return RelayOptions(output: output, endpointProviderIDs: ids, optionalProviderIDs: optionalProviderIDs,
                            refreshOptionalProviders: refreshOptional, renewClaude: ids.contains("claude"))
    }

    /// Claude's endpoint is polled at most once a minute; local sources keep the normal debounce.
    public static func debounce(enabled: [String: Bool], consent: DirectAccessConsent) -> TimeInterval {
        active(enabled: enabled, consent: consent).contains("claude") ? 60 : PublishDebounce.minInterval
    }
}
