import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Ephemeral session: no cookies, no URL cache, so tokens and usage payloads are never written to disk.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// The widget passes short timeouts so a refresh fits in its time budget.
    public init(requestTimeout: TimeInterval = 30, resourceTimeout: TimeInterval = 90) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageProviderError.network }
        return (data, http)
    }
}

/// A usable bearer credential. Never log or persist outside `CredentialStore`.
public struct AccessCredential: Sendable, Equatable {
    public let token: String
    public let accountID: String?
    /// Subscription label the credential store knows about (e.g. "max"); providers use it when the API omits it.
    public let plan: String?
    public init(token: String, accountID: String? = nil, plan: String? = nil) {
        self.token = token
        self.accountID = accountID
        self.plan = plan
    }
}

/// Supplies a valid credential, refreshing if needed. Throws `.unauthenticated` when none is available.
/// How a credential is obtained is outside the providers.
public protocol AccessTokenSource: Sendable {
    func credentials() async throws -> AccessCredential
}

/// Reads a bearer token (and optional account id) straight from a `CredentialStore`. No refresh.
public struct StoredTokenSource: AccessTokenSource {
    private let store: any CredentialStore
    private let tokenKey: String
    private let accountKey: String?

    public init(store: any CredentialStore, tokenKey: String, accountKey: String? = nil) {
        self.store = store
        self.tokenKey = tokenKey
        self.accountKey = accountKey
    }

    public func credentials() async throws -> AccessCredential {
        guard let token = try? store.read(tokenKey), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageProviderError.unauthenticated
        }
        let account = accountKey.flatMap { try? store.read($0) }
        return AccessCredential(token: token.trimmingCharacters(in: .whitespacesAndNewlines), accountID: account)
    }
}

/// Remembers a 429 so repeat calls inside the window never reach the network.
actor BackoffGate {
    private var blockedUntil: Date?

    func check(now: Date) -> Date? {
        guard let blockedUntil, blockedUntil > now else { return nil }
        return blockedUntil
    }

    func block(until date: Date) { blockedUntil = date }
}

enum RetryAfter {
    static func date(from response: HTTPURLResponse, now: Date, fallback: TimeInterval = 60) -> Date {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return now.addingTimeInterval(fallback)
        }
        if let seconds = TimeInterval(raw), seconds >= 0 { return now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: raw) ?? now.addingTimeInterval(fallback)
    }
}
