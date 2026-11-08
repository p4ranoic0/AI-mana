#if canImport(AImanaSignIn)
import CryptoKit
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

private func b64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@Suite struct PhoneLoginTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func loginRequestIsPKCEWithMinimalScope() throws {
        let request = ClaudeOAuth.beginLogin()
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(request.url.host == "claude.ai")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == "user:profile")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == b64url(Data(SHA256.hash(data: Data(request.verifier.utf8)))))
        #expect(items["state"] == request.state)
        #expect(request.verifier.count >= 43)
        #expect(ClaudeOAuth.beginLogin().verifier != request.verifier)   // fresh secret each time
    }

    @Test func pastedCodeMustCarryTheExpectedState() throws {
        #expect(try ClaudeOAuth.parsePastedCode("  abc123#st4te \n", expectedState: "st4te") == "abc123")
        #expect(throws: UsageProviderError.unauthenticated) { try ClaudeOAuth.parsePastedCode("abc#other", expectedState: "st4te") }
        #expect(throws: UsageProviderError.unauthenticated) { try ClaudeOAuth.parsePastedCode("nohash", expectedState: "st4te") }
        #expect(throws: UsageProviderError.unauthenticated) { try ClaudeOAuth.parsePastedCode("#st4te", expectedState: "st4te") }
    }

    @Test func exchangeSendsVerifierAndMapsTheSession() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"A1","refresh_token":"R1","expires_in":28800,"scope":"user:profile"}"#)])
        let request = ClaudeOAuth.beginLogin()
        let session = try await ClaudeOAuth.exchange(code: "the-code", request: request, transport: transport, now: now)
        #expect(session.accessToken == "A1" && session.refreshToken == "R1")
        #expect(session.expiresAt == now.addingTimeInterval(28800))
        let sent = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: String]
        #expect(sent["grant_type"] == "authorization_code")
        #expect(sent["code"] == "the-code")
        #expect(sent["code_verifier"] == request.verifier)
        #expect(transport.requests[0].url?.absoluteString == "https://platform.claude.com/v1/oauth/token")
    }

    @Test func badExchangeIsUnauthenticated() async {
        let transport = MockTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        await #expect(throws: UsageProviderError.unauthenticated) {
            _ = try await ClaudeOAuth.exchange(code: "x", request: ClaudeOAuth.beginLogin(), transport: transport, now: now)
        }
    }

    private func store(with session: ClaudeSession?) throws -> InMemoryCredentialStore {
        let s = InMemoryCredentialStore()
        if let session { try s.write(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), for: PhoneClaudeTokens.storeKey) }
        return s
    }

    @Test func noSessionMeansUnauthenticated() async {
        let tokens = PhoneClaudeTokens(store: InMemoryCredentialStore(), transport: MockTransport([]), clock: { now })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
    }

    @Test func validSessionIsUsedWithoutRefreshing() async throws {
        let transport = MockTransport([])
        let tokens = PhoneClaudeTokens(
            store: try store(with: ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600))),
            transport: transport, clock: { now })
        #expect(try await tokens.credentials().token == "A")
        #expect(transport.requests.isEmpty)
    }

    @Test func expiringSessionRefreshesAndPersistsTheRotatedToken() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#)])
        let backing = try store(with: ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(30)))
        let tokens = PhoneClaudeTokens(store: backing, transport: transport, clock: { now })
        #expect(try await tokens.credentials().token == "A2")
        let saved = try JSONDecoder().decode(ClaudeSession.self, from: Data(try backing.read(PhoneClaudeTokens.storeKey)!.utf8))
        #expect(saved.refreshToken == "R2")                          // rotation must be persisted, or the session is lost
        let sent = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: String]
        #expect(sent["grant_type"] == "refresh_token" && sent["refresh_token"] == "R")
    }

    @Test func concurrentCallsShareOneRefresh() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#)])
        let tokens = PhoneClaudeTokens(
            store: try store(with: ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(-5))),
            transport: transport, clock: { now })
        async let a = tokens.credentials()
        async let b = tokens.credentials()
        _ = try await (a, b)
        #expect(transport.requests.count == 1)   // a rotating refresh token must never be redeemed twice
    }

    @Test func revokedRefreshTokenIsUnauthenticated() async throws {
        let transport = MockTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        let tokens = PhoneClaudeTokens(
            store: try store(with: ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(-5))),
            transport: transport, clock: { now })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
    }

    @Test func signOutForgetsTheSession() async throws {
        let backing = try store(with: ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600)))
        let tokens = PhoneClaudeTokens(store: backing, transport: MockTransport([]), clock: { now })
        #expect(tokens.isSignedIn)
        try await tokens.signOut()
        #expect(!tokens.isSignedIn)
    }
}

/// A store whose delete always fails (e.g. the Keychain is locked).
private final class UndeletableStore: CredentialStore, @unchecked Sendable {
    let inner = InMemoryCredentialStore()
    func read(_ key: String) throws -> String? { try inner.read(key) }
    func write(_ value: String, for key: String) throws { try inner.write(value, for: key) }
    func delete(_ key: String) throws { throw UsageProviderError.network }
}

/// A one-holder async lock, like the cross-process file lock, so tests can see who waits for whom.
private final class SerialLock: ProcessLock, @unchecked Sendable {
    private actor Gate {
        private var held = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func acquire() async {
            while held { await withCheckedContinuation { waiters.append($0) } }
            held = true
        }
        func release() {
            held = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
    }
    private let gate = Gate()

    func withLock<T>(_ body: () async throws -> T) async throws -> T {
        await gate.acquire()
        do {
            let result = try await body()
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }
}

private actor Events {
    private(set) var log: [String] = []
    func add(_ event: String) { log.append(event) }
}

@Suite struct SessionKeeperOwnershipTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func renewDoesNotOverwriteNewerSignIn() async throws {
        let store = InMemoryCredentialStore()
        let keeper = SessionKeeper<ClaudeSession>(key: "k", store: store, processLock: NoProcessLock(), clock: { [now] in now },
                                                  renewSkew: 120) { old, _ in
            // While the old session renews, the user signs in again on this device.
            try store.write(String(decoding: try JSONEncoder().encode(
                ClaudeSession(accessToken: "NEW-A", refreshToken: "NEW-R", expiresAt: Date(timeIntervalSince1970: 1_800_003_600))),
                as: UTF8.self), for: "k")
            return ClaudeSession(accessToken: "RENEWED-A", refreshToken: "RENEWED-R", expiresAt: old.expiresAt.addingTimeInterval(3600))
        }
        try await keeper.save(ClaudeSession(accessToken: "OLD-A", refreshToken: "OLD-R", expiresAt: now.addingTimeInterval(-5)))
        let current = try await keeper.current()
        #expect(current.refreshToken == "NEW-R")
        #expect(keeper.load()?.refreshToken == "NEW-R")
    }

    private func keeper(store: InMemoryCredentialStore, events: Events) -> SessionKeeper<ClaudeSession> {
        SessionKeeper<ClaudeSession>(key: "k", store: store, processLock: SerialLock(), clock: { [now] in now },
                                     renewSkew: 120) { old, _ in
            await events.add("renew-start")
            try await Task.sleep(for: .milliseconds(150))
            await events.add("renew-end")
            return ClaudeSession(accessToken: "RENEWED-A", refreshToken: "RENEWED-R", expiresAt: old.expiresAt.addingTimeInterval(3600))
        }
    }

    @Test func signInDuringRenewalWaitsAndWins() async throws {
        let store = InMemoryCredentialStore()
        let events = Events()
        let keeper = keeper(store: store, events: events)
        try await keeper.save(ClaudeSession(accessToken: "OLD-A", refreshToken: "OLD-R", expiresAt: now.addingTimeInterval(-5)))
        async let renewed = keeper.current()
        try await Task.sleep(for: .milliseconds(50))
        try await keeper.save(ClaudeSession(accessToken: "NEW-A", refreshToken: "NEW-R", expiresAt: now.addingTimeInterval(3600)))
        await events.add("saved")
        _ = try await renewed
        #expect(await events.log == ["renew-start", "renew-end", "saved"])
        #expect(keeper.load()?.refreshToken == "NEW-R")
    }

    @Test func signOutDuringRenewalWaitsAndStaysSignedOut() async throws {
        let store = InMemoryCredentialStore()
        let events = Events()
        let keeper = keeper(store: store, events: events)
        try await keeper.save(ClaudeSession(accessToken: "OLD-A", refreshToken: "OLD-R", expiresAt: now.addingTimeInterval(-5)))
        async let renewed = keeper.current()
        try await Task.sleep(for: .milliseconds(50))
        try await keeper.delete()
        await events.add("deleted")
        _ = try? await renewed
        #expect(await events.log == ["renew-start", "renew-end", "deleted"])
        #expect(keeper.load() == nil)
    }

    @Test func deleteFailureSurfaces() async throws {
        let store = UndeletableStore()
        let tokens = PhoneClaudeTokens(store: store, transport: MockTransport([]), clock: { [now] in now })
        await #expect(throws: (any Error).self) { try await tokens.signOut() }
    }
}
#endif
