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

/// Unsigned JWT with the given payload, the shape OpenAI's id_token and access_token have.
private func jwt(_ payload: [String: Any]) -> String {
    let header = b64url(try! JSONSerialization.data(withJSONObject: ["alg": "none"]))
    return "\(header).\(b64url(try! JSONSerialization.data(withJSONObject: payload))).sig"
}

private func formFields(_ request: URLRequest) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func jsonFields(_ request: URLRequest) -> [String: String] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String] ?? [:]
}

/// Records requested sleeps instead of waiting.
private final class Sleeps: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [TimeInterval] = []
    func record(_ value: TimeInterval) { lock.withLock { values.append(value) } }
}

@Suite struct CodexLoginTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let idToken = jwt(["https://api.openai.com/auth": ["chatgpt_account_id": "acct-9", "chatgpt_plan_type": "plus"]])

    private func device(interval: TimeInterval = 5, expiresIn: TimeInterval = 900) -> CodexDeviceCode {
        CodexDeviceCode(verificationURL: CodexOAuth.verificationURL, userCode: "ABCD-1234", deviceAuthID: "dev-1",
                        interval: interval, expiresAt: now.addingTimeInterval(expiresIn))
    }

    // MARK: Device code request

    @Test func deviceCodeRequestMatchesTheCLI() async throws {
        let transport = MockTransport([.init(status: 200, body: #"""
            {"device_auth_id":"dev-1","user_code":"ABCD-1234","interval":"5","expires_at":"2027-01-15T08:20:00.123456+00:00"}
            """#)])
        let code = try await CodexOAuth.requestDeviceCode(transport: transport, now: now)
        #expect(code.userCode == "ABCD-1234" && code.deviceAuthID == "dev-1")
        #expect(code.interval == 5)                                         // sent as a string by the server
        #expect(code.verificationURL.absoluteString == "https://auth.openai.com/codex/device")
        #expect(abs(code.expiresAt.timeIntervalSince1970 - 1_800_001_200.123) < 0.01)   // server's microsecond timestamp
        let sent = transport.requests[0]
        #expect(sent.url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/usercode")
        #expect(sent.httpMethod == "POST")
        #expect(jsonFields(sent) == ["client_id": "app_EMoamEEZ73f0CkXaXp7hrann"])
    }

    @Test func deviceCodeAcceptsNumericIntervalAndMissingExpiry() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"device_auth_id":"d","usercode":"U","interval":7}"#)])
        let code = try await CodexOAuth.requestDeviceCode(transport: transport, now: now)
        #expect(code.userCode == "U" && code.interval == 7)
        #expect(code.expiresAt == now.addingTimeInterval(15 * 60))
    }

    @Test func disabledDeviceLoginIsReportedDistinctly() async {
        await #expect(throws: CodexLoginError.deviceCodeUnavailable) {
            _ = try await CodexOAuth.requestDeviceCode(transport: MockTransport([.init(status: 404, body: "")]), now: now)
        }
        await #expect(throws: CodexLoginError.deviceCodeUnavailable) {
            _ = try await CodexOAuth.requestDeviceCode(transport: MockTransport([.init(status: 403, body: "")]), now: now)
        }
        await #expect(throws: UsageProviderError.server(status: 503)) {
            _ = try await CodexOAuth.requestDeviceCode(transport: MockTransport([.init(status: 503, body: "")]), now: now)
        }
    }

    // MARK: Polling and exchange

    @Test func pollsUntilApprovedThenRedeemsWithTheServerVerifier() async throws {
        let transport = MockTransport([
            .init(status: 403, body: ""),                  // pending
            .init(status: 404, body: ""),                  // pending
            .init(status: 200, body: #"{"authorization_code":"auth-code","code_challenge":"ch","code_verifier":"ver+/="}"#),
            .init(status: 200, body: #"{"id_token":"\#(idToken)","access_token":"A1","refresh_token":"R1","expires_in":3600}"#),
        ])
        let sleeps = Sleeps()
        let session = try await CodexOAuth.completeDeviceLogin(device(), transport: transport, clock: { now },
                                                               sleep: { sleeps.record($0) })
        #expect(sleeps.values == [5, 5])
        #expect(session == CodexSession(accessToken: "A1", refreshToken: "R1", accountID: "acct-9", plan: "plus",
                                        expiresAt: now.addingTimeInterval(3600)))
        let poll = transport.requests[0]
        #expect(poll.url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/token")
        #expect(jsonFields(poll) == ["device_auth_id": "dev-1", "user_code": "ABCD-1234"])
        let exchange = transport.requests[3]
        #expect(exchange.url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(formFields(exchange) == ["grant_type": "authorization_code", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
                                         "code": "auth-code", "code_verifier": "ver+/=",
                                         "redirect_uri": "https://auth.openai.com/deviceauth/callback"])
        #expect(String(decoding: exchange.httpBody!, as: UTF8.self).contains("ver%2B%2F%3D"))   // never a bare `+`
    }

    @Test func unapprovedCodeExpires() async {
        let transport = MockTransport(Array(repeating: .init(status: 403, body: ""), count: 3))
        let slept = Sleeps()   // the fake clock advances by exactly what was slept
        await #expect(throws: CodexLoginError.expired) {
            _ = try await CodexOAuth.completeDeviceLogin(
                device(interval: 5, expiresIn: 8), transport: transport,
                clock: { [now] in now.addingTimeInterval(slept.values.reduce(0, +)) },
                sleep: { slept.record($0) })
        }
        #expect(slept.values == [5, 3])            // never sleeps past the code's expiry
        #expect(transport.requests.count == 3)     // one last poll right at expiry, then stop
    }

    @Test func pollingFailureStopsTheLogin() async {
        let transport = MockTransport([.init(status: 500, body: "")])
        await #expect(throws: UsageProviderError.server(status: 500)) {
            _ = try await CodexOAuth.completeDeviceLogin(device(), transport: transport, clock: { now }, sleep: { _ in })
        }
    }

    @Test func expiryFallsBackToTheAccessTokenExp() async throws {
        let access = jwt(["exp": 1_800_007_200, "https://api.openai.com/auth": ["chatgpt_account_id": "from-access"]])
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"\#(access)","refresh_token":"R"}"#)])
        let session = try await CodexOAuth.exchange(code: "c", verifier: "v", redirectURI: CodexOAuth.deviceRedirectURI,
                                                    transport: transport, now: now)
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_800_007_200))
        #expect(session.accountID == "from-access")
    }

    @Test func rejectedExchangeIsUnauthenticated() async {
        let transport = MockTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        await #expect(throws: UsageProviderError.unauthenticated) {
            _ = try await CodexOAuth.exchange(code: "x", request: CodexOAuth.beginBrowserLogin(), transport: transport, now: now)
        }
    }

    // MARK: Browser fallback

    @Test func browserLoginIsPKCEWithTheCLIParameters() throws {
        let request = CodexOAuth.beginBrowserLogin()
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(request.url.host == "auth.openai.com" && request.url.path == "/oauth/authorize")
        #expect(items["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(items["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(items["scope"] == "openid profile email offline_access")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == b64url(Data(SHA256.hash(data: Data(request.verifier.utf8)))))
        #expect(items["state"] == request.state)
        #expect(CodexOAuth.beginBrowserLogin().verifier != request.verifier)   // fresh secret each time
    }

    @Test func pastedRedirectMustCarryTheExpectedState() throws {
        let url = "http://127.0.0.1:1455/auth/callback?code=c%2B1&scope=openid&state=st4te"
        #expect(try CodexOAuth.parsePastedRedirect("  \(url)\n", expectedState: "st4te") == "c+1")
        #expect(try CodexOAuth.parsePastedRedirect("code=abc&state=st4te", expectedState: "st4te") == "abc")
        #expect(throws: UsageProviderError.unauthenticated) {
            try CodexOAuth.parsePastedRedirect("http://127.0.0.1:1455/auth/callback?code=abc&state=other", expectedState: "st4te")
        }
        #expect(throws: UsageProviderError.unauthenticated) {
            try CodexOAuth.parsePastedRedirect("http://127.0.0.1:1455/auth/callback?state=st4te", expectedState: "st4te")
        }
    }

    // MARK: Phone tokens

    private func store(with session: CodexSession?) throws -> InMemoryCredentialStore {
        let s = InMemoryCredentialStore()
        if let session { try s.write(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), for: PhoneCodexTokens.storeKey) }
        return s
    }

    @Test func noSessionMeansUnauthenticated() async {
        let tokens = PhoneCodexTokens(store: InMemoryCredentialStore(), transport: MockTransport([]), clock: { now })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
    }

    @Test func validSessionIsUsedWithItsAccountWithoutRefreshing() async throws {
        let transport = MockTransport([])
        let tokens = PhoneCodexTokens(
            store: try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: "acct-9", plan: "plus",
                                                expiresAt: now.addingTimeInterval(3600))),
            transport: transport, clock: { now })
        #expect(try await tokens.credentials() == AccessCredential(token: "A", accountID: "acct-9", plan: "plus"))
        #expect(transport.requests.isEmpty)
    }

    @Test func expiringSessionRefreshesAndPersistsTheRotatedToken() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":3600}"#)])
        let backing = try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: "acct-9",
                                                   expiresAt: now.addingTimeInterval(60)))
        let tokens = PhoneCodexTokens(store: backing, transport: transport, clock: { now })
        let credential = try await tokens.credentials()
        #expect(credential.token == "A2" && credential.accountID == "acct-9")   // account survives a refresh without id_token
        let saved = try JSONDecoder().decode(CodexSession.self, from: Data(try backing.read(PhoneCodexTokens.storeKey)!.utf8))
        #expect(saved.refreshToken == "R2")                                   // rotation must be persisted, or the session is lost
        #expect(transport.requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(jsonFields(transport.requests[0]) == ["grant_type": "refresh_token", "refresh_token": "R",
                                                      "client_id": "app_EMoamEEZ73f0CkXaXp7hrann"])
    }

    @Test func concurrentCallsShareOneRefresh() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":3600}"#)])
        let tokens = PhoneCodexTokens(
            store: try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: nil,
                                                expiresAt: now.addingTimeInterval(-5))),
            transport: transport, clock: { now })
        async let a = tokens.credentials()
        async let b = tokens.credentials()
        _ = try await (a, b)
        #expect(transport.requests.count == 1)   // a rotating refresh token must never be redeemed twice
    }

    @Test func revokedRefreshTokenIsUnauthenticated() async throws {
        let transport = MockTransport([.init(status: 401, body: #"{"error":{"code":"refresh_token_reused"}}"#)])
        let tokens = PhoneCodexTokens(
            store: try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: nil,
                                                expiresAt: now.addingTimeInterval(-5))),
            transport: transport, clock: { now })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
    }

    @Test func signOutForgetsTheSession() async throws {
        let backing = try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: nil,
                                                   expiresAt: now.addingTimeInterval(3600)))
        let tokens = PhoneCodexTokens(store: backing, transport: MockTransport([]), clock: { now })
        #expect(tokens.isSignedIn)
        try await tokens.signOut()
        #expect(!tokens.isSignedIn)
    }

    // MARK: End to end with the usage provider

    @Test func phoneSessionDrivesTheCodexUsageRequest() async throws {
        let transport = MockTransport([.init(status: 200, body: #"""
            {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"reset_at":1800003600,"limit_window_seconds":18000}}}
            """#)])
        let tokens = PhoneCodexTokens(
            store: try store(with: CodexSession(accessToken: "A", refreshToken: "R", accountID: "acct-9",
                                                expiresAt: now.addingTimeInterval(3600))),
            transport: MockTransport([]), clock: { now })
        let provider = HybridProvider(direct: CodexProvider(transport: transport, tokens: tokens, clock: { now }),
                                      relay: RelayFailing(), isDirectEnabled: { tokens.isSignedIn })
        let usage = try await provider.fetchUsage()
        #expect(usage.providerID == "codex" && usage.primary?.usedPercent == 12)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer A")
        #expect(transport.requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-9")
    }
}

private struct RelayFailing: UsageProvider {
    let id = "codex"
    let displayName = "OpenAI Codex"
    func fetchUsage() async throws -> UsageInfo { throw UsageProviderError.relayUnavailable }
}
#endif
