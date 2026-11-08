#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

private struct Relay: UsageProvider {
    let id: String
    let displayName = "Relay"
    func fetchUsage() async throws -> UsageInfo {
        UsageInfo(providerID: id, providerName: id,
                  windows: [UsageWindow(kind: .session, usedPercent: 42, windowMinutes: 300, resetsAt: nil)],
                  plan: nil, lastUpdated: Date())
    }
}

@Suite struct ConsentGatingTests {
    private let now = Date()

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "consent-gating-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    /// A Claude session saved by an earlier (personal) build, still valid.
    private func signedInClaude(_ transport: MockTransport) throws -> PhoneClaudeTokens {
        let store = InMemoryCredentialStore()
        let session = ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600))
        try store.write(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), for: PhoneClaudeTokens.storeKey)
        return PhoneClaudeTokens(store: store, transport: transport, clock: { [now] in now })
    }

    @Test func inheritedSessionWithoutConsentStaysRelay() async throws {
        try await withDefaults { defaults in
            let transport = MockTransport([.init(status: 200, body: ClaudeProviderTests.okBody)])
            let provider = PhoneDirectAccess.claude(tokens: try signedInClaude(transport), relay: Relay(id: "claude"),
                                                    consent: DirectAccessConsent(defaults: defaults),
                                                    transport: transport, gate: BackoffGate())
            #expect(try await provider.fetchUsage().primary?.usedPercent == 42)
            #expect(transport.requests.isEmpty)
        }
    }

    @Test func consentedSessionUsesDirect() async throws {
        try await withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            consent.grant(.claude)
            let transport = MockTransport([.init(status: 200, body: ClaudeProviderTests.okBody)])
            let provider = PhoneDirectAccess.claude(tokens: try signedInClaude(transport), relay: Relay(id: "claude"),
                                                    consent: consent, transport: transport, gate: BackoffGate())
            #expect(try await provider.fetchUsage().primary?.usedPercent == 18)
            #expect(transport.requests.count == 1)
        }
    }

    @Test func activeProvidersNeedConsentAndSession() async {
        await withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            #expect(PhoneDirectAccess.activeProviders(consent: consent, claudeSignedIn: true, codexSignedIn: true).isEmpty)
            consent.grant(.codex)
            #expect(PhoneDirectAccess.activeProviders(consent: consent, claudeSignedIn: true, codexSignedIn: true) == [.codex])
            #expect(PhoneDirectAccess.activeProviders(consent: consent, claudeSignedIn: true, codexSignedIn: false).isEmpty)
        }
    }

    @Test func revokingDropsThatProvidersSavedReading() async throws {
        try await withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            consent.grant(.claude)
            let store = SnapshotStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("revoke-\(UUID().uuidString).json"))
            try store.save([try await Relay(id: "claude").fetchUsage(), try await Relay(id: "codex").fetchUsage()])
            PhoneDirectAccess.revoke(.claude, consent: consent, store: store)
            #expect(!consent.isGranted(.claude))
            #expect(store.load().map(\.providerID) == ["codex"])
        }
    }

    @Test func notificationsTreatUnconsentedProvidersAsRelay() async {
        await withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            consent.grant(.claude)
            let split = PhoneDirectAccess.notificationSplit(consent: consent)
            #expect(split.phone == [.claude])
            #expect(split.relay == ["codex"])
        }
    }
}
#endif
