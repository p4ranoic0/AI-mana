import AImanaCore
import Foundation
import Testing
@testable import RelayDirect
@testable import RelayKit

@Suite struct DirectEndpointsTests {
    @Test func renewFlagReachesClaudeTokens() {
        let on = DirectEndpoints.claudeTokens(options: RelayOptions(endpointProviderIDs: ["claude"], renewClaude: true),
                                              log: { _ in })
        let off = DirectEndpoints.claudeTokens(options: RelayOptions(endpointProviderIDs: ["claude"]), log: { _ in })
        #expect(on.renew)
        #expect(!off.renew)
    }

    @Test func legacyMagicIDNoLongerRenews() {
        let tokens = DirectEndpoints.claudeTokens(options: RelayOptions(endpointProviderIDs: ["claude", "renewClaude"]),
                                                  log: { _ in })
        #expect(!tokens.renew)
    }

    @Test func factoryBuildsOnlyClaudeAndCodex() {
        let factory = DirectEndpoints.factory(log: { _ in })
        let options = RelayOptions(endpointProviderIDs: ["claude", "codex"])
        #expect(factory("claude", options)?.id == "claude")
        #expect(factory("codex", options)?.id == "codex")
        #expect(factory("grok", options) == nil)
    }
}

@Suite struct DirectEndpointsBackoffTests {
    @Test func factoryProvidersShareThePersistedBlock() async throws {
        let suite = "direct-endpoints-backoff-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        await BackoffGate.shared("claude", defaults: defaults).block(until: Date().addingTimeInterval(600))
        let provider = try #require(DirectEndpoints.factory(defaults: defaults, log: { _ in })("claude", RelayOptions()))
        // Blocked before any credential is read or request is sent.
        await #expect(throws: UsageProviderError.self) { try await provider.fetchUsage() }
        do { _ = try await provider.fetchUsage() } catch let error as UsageProviderError {
            guard case .rateLimited = error else { Issue.record("expected rateLimited, got \(error)"); return }
        }
    }
}

@Suite struct MacDirectOptionsTests {
    private func withConsent(_ body: (DirectAccessConsent) -> Void) {
        let suite = "mac-direct-options-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(DirectAccessConsent(defaults: defaults))
    }
    private let output = URL(fileURLWithPath: "/tmp/usage-relay.json")

    @Test func macOptionsRequireConsent() {
        withConsent { consent in
            let off = MacDirectOptions.make(output: output, enabled: ["claude": true, "codex": true], consent: consent)
            #expect(off.endpointProviderIDs.isEmpty)
            #expect(!off.renewClaude)
            consent.grant(.claude)
            let on = MacDirectOptions.make(output: output, enabled: ["claude": true, "codex": true], consent: consent)
            #expect(on.endpointProviderIDs == ["claude"])
            #expect(on.renewClaude)
        }
    }

    @Test func consentWithoutToggleStaysOff() {
        withConsent { consent in
            consent.grant(.codex)
            #expect(MacDirectOptions.make(output: output, enabled: [:], consent: consent).endpointProviderIDs.isEmpty)
        }
    }

    @Test func debounceSlowsOnlyForClaudeDirect() {
        withConsent { consent in
            #expect(MacDirectOptions.debounce(enabled: ["claude": true], consent: consent) == PublishDebounce.minInterval)
            consent.grant(.claude)
            #expect(MacDirectOptions.debounce(enabled: ["claude": true], consent: consent) == 60)
        }
    }
}

/// Answers, and lets the test revoke the consent while the "request" is in flight.
private final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = true
    var isOn: Bool { lock.withLock { on } }
    func off() { lock.withLock { on = false } }
}

private struct Answering: UsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let during: @Sendable () -> Void
    func fetchUsage() async throws -> UsageInfo {
        during()
        return UsageInfo(providerID: id, providerName: displayName, windows: [], plan: nil, lastUpdated: Date())
    }
}

@Suite struct ConsentGatedTests {
    @Test func revokedBeforeTheRequestNeverAsks() async {
        let gate = Switch()
        gate.off()
        let asked = Switch()   // stays on unless the inner provider runs
        let provider = ConsentGated(Answering(during: { asked.off() }), isAllowed: { gate.isOn })
        await #expect(throws: UsageProviderError.relayUnavailable) { _ = try await provider.fetchUsage() }
        #expect(asked.isOn)
    }

    @Test func revokedWhileInFlightDiscardsTheAnswer() async {
        let gate = Switch()
        let provider = ConsentGated(Answering(during: { gate.off() }), isAllowed: { gate.isOn })
        await #expect(throws: UsageProviderError.relayUnavailable) { _ = try await provider.fetchUsage() }
    }

    @Test func allowedPassesThrough() async throws {
        let provider = ConsentGated(Answering(during: { }), isAllowed: { true })
        #expect(try await provider.fetchUsage().providerID == "claude")
    }

    @Test func factoryGatesEveryDirectProvider() async {
        let factory = DirectEndpoints.factory(log: { _ in }, isAllowed: { _ in false })
        let provider = factory("claude", RelayOptions(endpointProviderIDs: ["claude"]))
        // Refused before any credential is read.
        await #expect(throws: UsageProviderError.relayUnavailable) { _ = try await provider?.fetchUsage() }
    }
}
