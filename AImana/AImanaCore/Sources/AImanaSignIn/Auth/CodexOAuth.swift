import AImanaCore
import CryptoKit
import Foundation
import Security

/// A ChatGPT (Codex) sign-in owned by this device. It is a separate session from the one the Codex CLI keeps in the
/// Mac's `~/.codex/auth.json`, so renewing it can never invalidate (or be invalidated by) the Mac's tokens.
public struct CodexSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    /// The ChatGPT workspace the usage endpoint needs in `ChatGPT-Account-Id` (from the id_token's auth claims).
    public let accountID: String?
    public let plan: String?
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, accountID: String?, plan: String? = nil, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.plan = plan
        self.expiresAt = expiresAt
    }
}

/// A pending device-code sign-in: the user opens `verificationURL` on any browser and types `userCode`.
public struct CodexDeviceCode: Sendable, Equatable {
    public let verificationURL: URL
    public let userCode: String
    /// Opaque handle for polling. Keep it in memory only.
    let deviceAuthID: String
    public let interval: TimeInterval
    public let expiresAt: Date
}

/// What `/deviceauth/token` hands back once the user approves: an authorization code plus the PKCE pair the
/// server generated for this device login, redeemed at `/oauth/token` like a normal authorization-code grant.
struct CodexDeviceAuthorization: Sendable, Equatable {
    let authorizationCode: String
    let codeVerifier: String
}

/// Fallback browser login (PKCE, loopback redirect). There is no listener on the phone, so Safari ends on an
/// unreachable `127.0.0.1` page and the user pastes that address back into the app.
public struct CodexLoginRequest: Sendable {
    public let url: URL
    /// PKCE secret. Keep it in memory only until the code is exchanged.
    public let verifier: String
    public let state: String
}

public enum CodexLoginError: Error, Sendable, Equatable {
    /// `/deviceauth/usercode` refused the request (the Codex CLI reads 404 as "device code login is not enabled").
    /// For a ChatGPT account this is usually a security setting the user has to turn on.
    case deviceCodeUnavailable
    /// The one-time code was not approved before it expired (15 minutes).
    case expired
}

/// OpenAI's ChatGPT sign-in as the Codex CLI does it (openai/codex, `codex-rs/login`):
/// - device code: `POST {issuer}/api/accounts/deviceauth/usercode` `{client_id}` → `{device_auth_id, user_code, interval}`;
///   the user enters the code at `{issuer}/codex/device`; poll `POST …/deviceauth/token` `{device_auth_id, user_code}`
///   (403/404 = still pending) until it returns `{authorization_code, code_verifier}`, then redeem that at
///   `/oauth/token` with `redirect_uri = {issuer}/deviceauth/callback` (form-encoded).
/// - refresh: `POST /oauth/token` JSON `{grant_type: refresh_token, client_id, refresh_token}`. Refresh tokens rotate.
public enum CodexOAuth {
    static let issuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let tokenURL = URL(string: "\(issuer)/oauth/token")!
    static let userCodeURL = URL(string: "\(issuer)/api/accounts/deviceauth/usercode")!
    static let deviceTokenURL = URL(string: "\(issuer)/api/accounts/deviceauth/token")!
    static let verificationURL = URL(string: "\(issuer)/codex/device")!
    static let deviceRedirectURI = "\(issuer)/deviceauth/callback"
    static let browserRedirectURI = "http://127.0.0.1:1455/auth/callback"
    static let scope = "openid profile email offline_access"
    /// The CLI's own limit for a device code; used when the server omits `expires_at`.
    static let deviceCodeLifetime: TimeInterval = 15 * 60
    /// Used only when neither `expires_in` nor the access token's `exp` says when it expires.
    static let fallbackLifetime: TimeInterval = 3600

    // MARK: Device code

    public static func requestDeviceCode(transport: any HTTPTransport, now: Date = Date()) async throws -> CodexDeviceCode {
        let (data, response) = try await post(userCodeURL, json: ["client_id": clientID], transport: transport)
        switch response.statusCode {
        case 200:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = json["device_auth_id"] as? String, !id.isEmpty,
                  let code = (json["user_code"] ?? json["usercode"]) as? String, !code.isEmpty else {
                throw UsageProviderError.decoding
            }
            // The server sends `interval` as a string ("5"); accept a number too.
            let interval = (json["interval"] as? NSNumber)?.doubleValue
                ?? (json["interval"] as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 5
            let expires = (json["expires_at"] as? String).flatMap(parseISODate) ?? now.addingTimeInterval(deviceCodeLifetime)
            return CodexDeviceCode(verificationURL: verificationURL, userCode: code, deviceAuthID: id,
                                   interval: max(interval, 0), expiresAt: expires)
        case 403, 404: throw CodexLoginError.deviceCodeUnavailable
        case 429: throw UsageProviderError.rateLimited(until: RetryAfter.date(from: response, now: now))
        default: throw UsageProviderError.server(status: response.statusCode)
        }
    }

    /// One poll. `nil` means the user has not approved yet.
    static func pollDeviceAuthorization(_ device: CodexDeviceCode,
                                        transport: any HTTPTransport) async throws -> CodexDeviceAuthorization? {
        let (data, response) = try await post(deviceTokenURL, json: ["device_auth_id": device.deviceAuthID,
                                                                     "user_code": device.userCode], transport: transport)
        switch response.statusCode {
        case 200:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let code = json["authorization_code"] as? String, !code.isEmpty,
                  let verifier = json["code_verifier"] as? String, !verifier.isEmpty else { throw UsageProviderError.decoding }
            return CodexDeviceAuthorization(authorizationCode: code, codeVerifier: verifier)
        case 403, 404: return nil
        case 400, 401: throw UsageProviderError.unauthenticated
        default: throw UsageProviderError.server(status: response.statusCode)
        }
    }

    /// Polls at the server's interval until the user approves the code, then redeems it for this device's session.
    /// Cancelling the calling task stops the polling.
    public static func completeDeviceLogin(_ device: CodexDeviceCode, transport: any HTTPTransport,
                                           clock: @escaping @Sendable () -> Date = { Date() },
                                           sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                                               try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
                                           }) async throws -> CodexSession {
        while true {
            try Task.checkCancellation()
            if let authorization = try await pollDeviceAuthorization(device, transport: transport) {
                return try await exchange(code: authorization.authorizationCode, verifier: authorization.codeVerifier,
                                          redirectURI: deviceRedirectURI, transport: transport, now: clock())
            }
            let remaining = device.expiresAt.timeIntervalSince(clock())
            guard remaining > 0 else { throw CodexLoginError.expired }
            try await sleep(min(max(device.interval, 1), remaining))
        }
    }

    // MARK: Browser fallback

    private static func randomBase64URL(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func beginBrowserLogin() -> CodexLoginRequest {
        let verifier = randomBase64URL(bytes: 64)
        let state = randomBase64URL(bytes: 32)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: browserRedirectURI), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"), .init(name: "state", value: state),
        ]
        return CodexLoginRequest(url: components.url!, verifier: verifier, state: state)
    }

    /// Accepts the full address Safari shows (`http://127.0.0.1:1455/auth/callback?code=…&state=…`) or just its query.
    /// The state must match what this device generated.
    public static func parsePastedRedirect(_ raw: String, expectedState: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.contains("?") ? String(trimmed[trimmed.index(after: trimmed.firstIndex(of: "?")!)...]) : trimmed
        var components = URLComponents()
        components.percentEncodedQuery = query.split(separator: "#", maxSplits: 1).first.map(String.init) ?? query
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let code = value("code"), !code.isEmpty, value("state") == expectedState else {
            throw UsageProviderError.unauthenticated
        }
        return code
    }

    public static func exchange(code: String, request: CodexLoginRequest, transport: any HTTPTransport,
                                now: Date = Date()) async throws -> CodexSession {
        try await exchange(code: code, verifier: request.verifier, redirectURI: browserRedirectURI,
                           transport: transport, now: now)
    }

    // MARK: Token endpoint

    static func exchange(code: String, verifier: String, redirectURI: String, transport: any HTTPTransport,
                         now: Date) async throws -> CodexSession {
        // The CLI sends the code exchange form-encoded.
        let body = formEncode([("grant_type", "authorization_code"), ("client_id", clientID), ("code", code),
                               ("redirect_uri", redirectURI), ("code_verifier", verifier)])
        var request = tokenRequest(contentType: "application/x-www-form-urlencoded")
        request.httpBody = Data(body.utf8)
        return try await token(request, transport: transport, now: now, previous: nil)
    }

    public static func refresh(_ session: CodexSession, transport: any HTTPTransport,
                               now: Date = Date()) async throws -> CodexSession {
        // The CLI sends refreshes as JSON.
        var request = tokenRequest(contentType: "application/json")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "client_id": clientID, "refresh_token": session.refreshToken,
        ])
        return try await token(request, transport: transport, now: now, previous: session)
    }

    private static func tokenRequest(contentType: String) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AImana/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func token(_ request: URLRequest, transport: any HTTPTransport, now: Date,
                              previous: CodexSession?) async throws -> CodexSession {
        let (data, response) = try await send(request, transport: transport)
        switch response.statusCode {
        case 200:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let access = json["access_token"] as? String, !access.isEmpty,
                  let refresh = (json["refresh_token"] as? String) ?? previous?.refreshToken, !refresh.isEmpty else {
                throw UsageProviderError.decoding
            }
            // A refresh may omit the id_token; the account it names does not change, so keep the previous one.
            let idClaims = (json["id_token"] as? String).flatMap(authClaims)
            let accessClaims = authClaims(fromJWT: access)
            let account = (idClaims?["chatgpt_account_id"] as? String) ?? (accessClaims?["chatgpt_account_id"] as? String)
                ?? previous?.accountID
            let plan = (idClaims?["chatgpt_plan_type"] as? String) ?? (accessClaims?["chatgpt_plan_type"] as? String)
                ?? previous?.plan
            let expires: Date
            if let lifetime = (json["expires_in"] as? NSNumber)?.doubleValue {
                expires = now.addingTimeInterval(lifetime)
            } else if let exp = (jwtPayload(access)?["exp"] as? NSNumber)?.doubleValue {
                expires = Date(timeIntervalSince1970: exp)   // the CLI reads expiry from the access token too
            } else {
                expires = now.addingTimeInterval(fallbackLifetime)
            }
            return CodexSession(accessToken: access, refreshToken: refresh, accountID: account, plan: plan, expiresAt: expires)
        case 400, 401, 403: throw UsageProviderError.unauthenticated
        case 429: throw UsageProviderError.rateLimited(until: RetryAfter.date(from: response, now: now))
        default: throw UsageProviderError.server(status: response.statusCode)
        }
    }

    // MARK: Helpers

    /// `application/x-www-form-urlencoded` with only RFC 3986 unreserved characters left bare, so `+`, `&`, `=`
    /// and `/` inside a code or verifier can never be misread.
    static func formEncode(_ pairs: [(String, String)]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text }
        return pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    private static func post(_ url: URL, json: [String: String],
                             transport: any HTTPTransport) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AImana/1.0", forHTTPHeaderField: "User-Agent")
        return try await send(request, transport: transport)
    }

    private static func send(_ request: URLRequest, transport: any HTTPTransport) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) }
        catch let error as UsageProviderError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageProviderError.network }
    }

    /// Payload of a JWT, without verifying the signature: it only selects which workspace to ask about,
    /// and the server enforces the token's real permissions.
    static func jwtPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The `https://api.openai.com/auth` claim set, which carries `chatgpt_account_id` and `chatgpt_plan_type`.
    static func authClaims(fromJWT jwt: String) -> [String: Any]? {
        jwtPayload(jwt)?["https://api.openai.com/auth"] as? [String: Any]
    }

    private static func parseISODate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Supplies the device's own ChatGPT access token and workspace id, renewing the token shortly before it expires.
/// The rotating refresh token is persisted before the new access token is handed out; concurrent callers, in this
/// process or in the widget, share a single renewal (see `SessionKeeper`).
public final class PhoneCodexTokens: AccessTokenSource, @unchecked Sendable {
    public static let storeKey = "codex.phone.session"
    static let renewSkew: TimeInterval = 300   // the CLI renews within 5 minutes of expiry

    private let keeper: SessionKeeper<CodexSession>

    /// `processLock` must be shared by every process that renews this session (the app and the widget); see
    /// `AppGroup.codexTokens`.
    public init(store: any CredentialStore, transport: any HTTPTransport = URLSessionTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }, processLock: any ProcessLock = NoProcessLock()) {
        keeper = SessionKeeper(key: Self.storeKey, store: store, processLock: processLock, clock: clock,
                               renewSkew: Self.renewSkew) { session, now in
            try await CodexOAuth.refresh(session, transport: transport, now: now)
        }
    }

    public var isSignedIn: Bool { keeper.load() != nil }

    public func save(_ session: CodexSession) async throws { try await keeper.save(session) }

    public func signOut() async throws { try await keeper.delete() }

    private func credential(_ session: CodexSession) -> AccessCredential {
        AccessCredential(token: session.accessToken, accountID: session.accountID, plan: session.plan)
    }

    public func credentials() async throws -> AccessCredential {
        credential(try await keeper.current())
    }
}
