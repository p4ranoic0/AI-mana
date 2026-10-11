import Foundation

/// When the relay may ask a provider CLI to renew its own session. The CLI owns the credential; the relay only
/// nudges it, and never more often than `cooldown`.
public enum RenewalPolicy {
    /// Renew when the access token has this little time left (or is already expired).
    public static let expirySkew: TimeInterval = 120
    public static let cooldown: TimeInterval = 20 * 60

    public static func shouldAttempt(expiresAt: Date?, lastAttempt: Date?, now: Date) -> Bool {
        guard let expiresAt else { return false }
        guard expiresAt.timeIntervalSince(now) <= expirySkew else { return false }
        if let lastAttempt, lastAttempt <= now, now.timeIntervalSince(lastAttempt) < cooldown { return false }
        return true
    }
}
