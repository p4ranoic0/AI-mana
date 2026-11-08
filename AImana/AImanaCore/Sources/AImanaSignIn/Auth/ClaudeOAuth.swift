import AImanaCore
import CryptoKit
import Foundation
import Security

/// A Claude sign-in owned by this device. It is a separate session from the one the Claude CLI holds on a Mac,
/// so renewing it can never invalidate (or be invalidated by) the Mac's tokens.
public struct ClaudeSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct ClaudeLoginRequest: Sendable {
    public let url: URL
    /// PKCE secret. Keep it in memory only until the code is exchanged.
    public let verifier: String
    public let state: String
}

/// Claude OAuth with PKCE using the "paste the code" redirect: the browser shows `code#state`, the user pastes it
/// into the app. The permission requested is only `user:profile`, which is all reading usage needs.
public enum ClaudeOAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let scope = "user:profile"

    private static func randomBase64URL(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func beginLogin() -> ClaudeLoginRequest {
        let verifier = randomBase64URL(bytes: 32)
        let state = randomBase64URL(bytes: 24)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            .init(name: "code", value: "true"), .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scope), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
        ]
        return ClaudeLoginRequest(url: components.url!, verifier: verifier, state: state)
    }

    /// The page shows `code#state`; the state must match what this device generated.
    public static func parsePastedCode(_ raw: String, expectedState: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, parts[1] == expectedState else { throw UsageProviderError.unauthenticated }
        return parts[0]
    }

    public static func exchange(code: String, request: ClaudeLoginRequest, transport: any HTTPTransport,
                                now: Date = Date()) async throws -> ClaudeSession {
        try await token(body: ["grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
                               "client_id": clientID, "code_verifier": request.verifier, "state": request.state],
                        transport: transport, now: now, fallbackRefresh: nil)
    }

    public static func refresh(_ session: ClaudeSession, transport: any HTTPTransport,
                               now: Date = Date()) async throws -> ClaudeSession {
        try await token(body: ["grant_type": "refresh_token", "refresh_token": session.refreshToken, "client_id": clientID],
                        transport: transport, now: now, fallbackRefresh: session.refreshToken)
    }

    private static func token(body: [String: String], transport: any HTTPTransport, now: Date,
                              fallbackRefresh: String?) async throws -> ClaudeSession {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AImana/1.0", forHTTPHeaderField: "User-Agent")
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch let error as UsageProviderError { throw error }
        catch { throw UsageProviderError.network }

        switch response.statusCode {
        case 200:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let access = json["access_token"] as? String, !access.isEmpty,
                  let refresh = (json["refresh_token"] as? String) ?? fallbackRefresh,
                  let lifetime = (json["expires_in"] as? NSNumber)?.doubleValue else { throw UsageProviderError.decoding }
            return ClaudeSession(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(lifetime))
        case 400, 401, 403: throw UsageProviderError.unauthenticated
        case 429: throw UsageProviderError.rateLimited(until: RetryAfter.date(from: response, now: now))
        default: throw UsageProviderError.server(status: response.statusCode)
        }
    }
}

/// Supplies the device's own Claude access token, renewing it shortly before it expires. The rotating refresh token
/// is persisted before the new access token is handed out; concurrent callers, in this process or in the widget,
/// share a single renewal (see `SessionKeeper`).
public final class PhoneClaudeTokens: AccessTokenSource, @unchecked Sendable {
    public static let storeKey = "claude.phone.session"
    static let renewSkew: TimeInterval = 120

    private let keeper: SessionKeeper<ClaudeSession>

    /// `processLock` must be shared by every process that renews this session (the app and the widget); see
    /// `AppGroup.claudeTokens`.
    public init(store: any CredentialStore, transport: any HTTPTransport = URLSessionTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }, processLock: any ProcessLock = NoProcessLock()) {
        keeper = SessionKeeper(key: Self.storeKey, store: store, processLock: processLock, clock: clock,
                               renewSkew: Self.renewSkew) { session, now in
            try await ClaudeOAuth.refresh(session, transport: transport, now: now)
        }
    }

    public var isSignedIn: Bool { keeper.load() != nil }

    public func save(_ session: ClaudeSession) async throws { try await keeper.save(session) }

    public func signOut() async throws { try await keeper.delete() }

    private func credential(_ session: ClaudeSession) -> AccessCredential { AccessCredential(token: session.accessToken) }

    public func credentials() async throws -> AccessCredential {
        credential(try await keeper.current())
    }
}
