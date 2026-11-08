import AImanaCore
import Foundation

/// A phone sign-in whose refresh token rotates: redeeming a refresh token that was already used ends the session.
protocol RotatingSession: Codable, Sendable {
    var refreshToken: String { get }
    var expiresAt: Date { get }
}

extension ClaudeSession: RotatingSession {}
extension CodexSession: RotatingSession {}

/// Keeps one rotating session in a `CredentialStore` and renews it shortly before it expires.
///
/// The app and the widget each hold their own keeper over the same Keychain item, so a renewal runs inside a
/// cross-process lock and re-reads the store first: whoever gets the lock second finds the renewed session and uses
/// it instead of redeeming the (now consumed) refresh token. Inside one process concurrent callers share one renewal.
/// The rotated refresh token is persisted before the lock is released and before the new access token is handed out.
final class SessionKeeper<Session: RotatingSession>: @unchecked Sendable {
    typealias Renew = @Sendable (Session, Date) async throws -> Session

    private let key: String
    private let store: any CredentialStore
    private let processLock: any ProcessLock
    private let clock: @Sendable () -> Date
    private let renewSkew: TimeInterval
    private let renew: Renew
    private let lock = NSLock()
    private var refreshing: Task<Session, Error>?

    init(key: String, store: any CredentialStore, processLock: any ProcessLock, clock: @escaping @Sendable () -> Date,
         renewSkew: TimeInterval, renew: @escaping Renew) {
        self.key = key
        self.store = store
        self.processLock = processLock
        self.clock = clock
        self.renewSkew = renewSkew
        self.renew = renew
    }

    func load() -> Session? {
        guard let text = (try? store.read(key)) ?? nil else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(text.utf8))
    }

    /// A new sign-in. Runs under the renewal lock, so it never interleaves with a renewal in this or another process.
    func save(_ session: Session) async throws {
        try await locked { try write(session) }
    }

    /// Signing out. Same lock: a renewal in flight finishes first and cannot bring the session back afterwards.
    func delete() async throws {
        try await locked { try store.delete(key) }
    }

    private func write(_ session: Session) throws {
        try store.write(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), for: key)
    }

    private func locked(_ body: () throws -> Void) async throws {
        do { try await processLock.withLock { try body() } }
        catch is ProcessLockError { throw UsageProviderError.network }
    }

    private func isFresh(_ session: Session) -> Bool { session.expiresAt.timeIntervalSince(clock()) > renewSkew }

    /// A session that is valid for at least `renewSkew`, renewing it if needed.
    func current() async throws -> Session {
        guard let session = load() else { throw UsageProviderError.unauthenticated }
        if isFresh(session) { return session }

        let task: Task<Session, Error> = lock.withLock {
            if let refreshing { return refreshing }
            let created = Task<Session, Error> {
                defer { self.lock.withLock { self.refreshing = nil } }
                return try await self.renewShared()
            }
            refreshing = created
            return created
        }
        return try await task.value
    }

    private func renewShared() async throws -> Session {
        do {
            return try await processLock.withLock {
                // The app or the widget may have renewed while this one waited for the lock.
                guard let stored = load() else { throw UsageProviderError.unauthenticated }
                if isFresh(stored) { return stored }
                do {
                    return try await renewAndPersist(stored)
                } catch UsageProviderError.unauthenticated {
                    // `invalid_grant`: before declaring the sign-in lost, look once more. A process that did not take
                    // the lock (e.g. an older build) may have just rotated the token.
                    guard let latest = load(), latest.refreshToken != stored.refreshToken else {
                        throw UsageProviderError.unauthenticated
                    }
                    if isFresh(latest) { return latest }
                    return try await renewAndPersist(latest)
                }
            }
        } catch is ProcessLockError {
            throw UsageProviderError.network   // transient: the holder is still working; keep the stale reading
        }
    }

    private func renewAndPersist(_ session: Session) async throws -> Session {
        let renewed = try await renew(session, clock())
        // Signed out while the request was in flight: do not bring the session back.
        guard let current = load() else { throw UsageProviderError.unauthenticated }
        // Signed in again (or renewed elsewhere) meanwhile: that newer session wins and is never overwritten.
        guard current.refreshToken == session.refreshToken else { return current }
        try write(renewed)   // persist the rotated refresh token first (already under the lock)
        return renewed
    }
}
