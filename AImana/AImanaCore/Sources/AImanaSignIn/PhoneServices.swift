import AImanaCore
import Foundation

public extension AppGroup {
    /// The phone and widget share a lock when renewing the same Claude session.
    static func claudeTokens(transport: any HTTPTransport = URLSessionTransport(),
                             lockTimeout: TimeInterval = 15) -> PhoneClaudeTokens {
        PhoneClaudeTokens(store: keychain(), transport: transport,
                          processLock: lock("claude-session", timeout: lockTimeout))
    }

    /// The phone and widget share a lock when renewing the same Codex session.
    static func codexTokens(transport: any HTTPTransport = URLSessionTransport(),
                            lockTimeout: TimeInterval = 15) -> PhoneCodexTokens {
        PhoneCodexTokens(store: keychain(), transport: transport,
                         processLock: lock("codex-session", timeout: lockTimeout))
    }
}

public extension CredentialKey {
    static let claudeToken = "claude.accessToken"
    static let codexToken = "codex.accessToken"
    static let codexAccountID = "codex.accountID"
}

public extension PhoneSignInProbe {
    static func claude(_ tokens: PhoneClaudeTokens) -> PhoneSignInProbe {
        PhoneSignInProbe(providerID: "claude", isSignedIn: { tokens.isSignedIn },
                         renew: { _ = try await tokens.credentials() })
    }

    static func codex(_ tokens: PhoneCodexTokens) -> PhoneSignInProbe {
        PhoneSignInProbe(providerID: "codex", isSignedIn: { tokens.isSignedIn },
                         renew: { _ = try await tokens.credentials() })
    }
}

/// How the app and the widget combine this device's sign-ins with the relay. One place, so both apply the same rule:
/// a stored session is used only while the user's consent for that provider is current (`DirectAccessConsent`).
public enum PhoneDirectAccess {
    /// Providers whose direct access is on right now: consent given and a session stored.
    public static func activeProviders(consent: DirectAccessConsent, claudeSignedIn: Bool,
                                       codexSignedIn: Bool) -> Set<DirectProvider> {
        var active: Set<DirectProvider> = []
        if claudeSignedIn, consent.isGranted(.claude) { active.insert(.claude) }
        if codexSignedIn, consent.isGranted(.codex) { active.insert(.codex) }
        return active
    }

    public static func claude(tokens: PhoneClaudeTokens, relay: any UsageProvider, consent: DirectAccessConsent,
                              transport: any HTTPTransport = URLSessionTransport(),
                              gate: BackoffGate = .shared("claude", defaults: DisplayPreferences.shared)) -> any UsageProvider {
        HybridProvider(direct: ClaudeProvider(transport: transport, tokens: tokens, gate: gate), relay: relay,
                       isDirectEnabled: { consent.isGranted(.claude) && tokens.isSignedIn })
    }

    public static func codex(tokens: PhoneCodexTokens, relay: any UsageProvider, consent: DirectAccessConsent,
                             transport: any HTTPTransport = URLSessionTransport(),
                             gate: BackoffGate = .shared("codex", defaults: DisplayPreferences.shared)) -> any UsageProvider {
        HybridProvider(direct: CodexProvider(transport: transport, tokens: tokens, gate: gate), relay: relay,
                       isDirectEnabled: { consent.isGranted(.codex) && tokens.isSignedIn })
    }

    /// Withdraws the consent and forgets the saved reading, which may have come from direct access: the next refresh
    /// shows the relay's data, never the old direct one.
    public static func revoke(_ provider: DirectProvider, consent: DirectAccessConsent,
                              store: SnapshotStore = AppGroup.snapshotStore()) {
        consent.revoke(provider)
        try? store.save(store.load().filter { $0.providerID != provider.rawValue })
    }

    /// Consented providers get this phone's sign-in alerts; the others are judged by what the relay reports.
    public static func notificationSplit(consent: DirectAccessConsent) -> (phone: [DirectProvider], relay: [String]) {
        let phone = DirectProvider.allCases.filter(consent.isGranted)
        return (phone, DirectProvider.allCases.filter { !phone.contains($0) }.map(\.rawValue))
    }

#if canImport(UserNotifications)
    public static func notificationDelivery(claude: PhoneClaudeTokens, codex: PhoneCodexTokens,
                                            consent: DirectAccessConsent) -> NotificationDelivery {
        let split = notificationSplit(consent: consent)
        let probes: [PhoneSignInProbe] = split.phone.map { $0 == .claude ? .claude(claude) : .codex(codex) }
        return NotificationDelivery(signIns: probes, macRelayProviderIDs: split.relay)
    }
#endif
}
