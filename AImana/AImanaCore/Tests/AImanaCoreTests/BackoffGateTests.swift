#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

@Suite struct BackoffGateTests {
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "backoff-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func blockSurvivesNewInstance() async {
        await withDefaults { defaults in
            await BackoffGate.shared("claude", defaults: defaults).block(until: now.addingTimeInterval(600))
            let fresh = BackoffGate.shared("claude", defaults: defaults)
            #expect(await fresh.check(now: now.addingTimeInterval(10)) == now.addingTimeInterval(600))
            #expect(defaults.object(forKey: "backoff.claude.until") != nil)
        }
    }

    @Test func expiredBlockClears() async {
        await withDefaults { defaults in
            await BackoffGate.shared("codex", defaults: defaults).block(until: now.addingTimeInterval(5))
            #expect(await BackoffGate.shared("codex", defaults: defaults).check(now: now.addingTimeInterval(6)) == nil)
        }
    }

    @Test func providersDoNotShareABlock() async {
        await withDefaults { defaults in
            await BackoffGate.shared("claude", defaults: defaults).block(until: now.addingTimeInterval(600))
            #expect(await BackoffGate.shared("codex", defaults: defaults).check(now: now) == nil)
        }
    }

    @Test func earlierInstanceSeesALaterBlockFromAnother() async {
        await withDefaults { defaults in
            let app = BackoffGate.shared("claude", defaults: defaults)
            await app.block(until: now.addingTimeInterval(60))
            await BackoffGate.shared("claude", defaults: defaults).block(until: now.addingTimeInterval(600))
            #expect(await app.check(now: now.addingTimeInterval(120)) == now.addingTimeInterval(600))
        }
    }

    @Test func anEarlierBlockNeverShortensALaterOne() async {
        await withDefaults { defaults in
            await BackoffGate.shared("claude", defaults: defaults).block(until: now.addingTimeInterval(600))
            let other = BackoffGate.shared("claude", defaults: defaults)
            await other.block(until: now.addingTimeInterval(60))
            #expect(await other.check(now: now.addingTimeInterval(120)) == now.addingTimeInterval(600))
            #expect(await BackoffGate.shared("claude", defaults: defaults).check(now: now.addingTimeInterval(120))
                    == now.addingTimeInterval(600))
        }
    }

    @Test func inMemoryGateStaysInMemory() async {
        await BackoffGate().block(until: now.addingTimeInterval(600))
        #expect(await BackoffGate().check(now: now) == nil)
    }

    @Test func claude429ThenSecondProviderInstanceDoesNotCallNetwork() async throws {
        try await withDefaults { defaults in
            let transport = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "120"])])
            let first = ClaudeProvider(transport: transport, tokens: FixedTokens(), clock: { now },
                                       gate: .shared("claude", defaults: defaults))
            await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) {
                try await first.fetchUsage()
            }
            let second = ClaudeProvider(transport: transport, tokens: FixedTokens(), clock: { now.addingTimeInterval(30) },
                                        gate: .shared("claude", defaults: defaults))
            await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) {
                try await second.fetchUsage()
            }
            #expect(transport.requests.count == 1)
        }
    }

    @Test func codexHonorsASharedGate() async throws {
        await withDefaults { defaults in
            await BackoffGate.shared("codex", defaults: defaults).block(until: now.addingTimeInterval(60))
            let transport = MockTransport([])
            let provider = CodexProvider(transport: transport, tokens: FixedTokens(), clock: { now },
                                         gate: .shared("codex", defaults: defaults))
            await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(60))) {
                try await provider.fetchUsage()
            }
            #expect(transport.requests.isEmpty)
        }
    }
}
#endif
