import Foundation

/// Secret storage abstraction. Production uses `KeychainService`; tests use `InMemoryCredentialStore`.
public protocol CredentialStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    public init() {}

    public func read(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    public func write(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}
