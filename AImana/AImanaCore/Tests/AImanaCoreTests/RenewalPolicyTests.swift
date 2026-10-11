import Foundation
import Testing
@testable import AImanaCore

@Suite struct RenewalPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func healthyTokenIsLeftAlone() {
        #expect(!RenewalPolicy.shouldAttempt(expiresAt: now.addingTimeInterval(3600), lastAttempt: nil, now: now))
    }

    @Test func expiredOrAboutToExpireTriggersAnAttempt() {
        #expect(RenewalPolicy.shouldAttempt(expiresAt: now.addingTimeInterval(-1), lastAttempt: nil, now: now))
        #expect(RenewalPolicy.shouldAttempt(expiresAt: now.addingTimeInterval(60), lastAttempt: nil, now: now))
        #expect(!RenewalPolicy.shouldAttempt(expiresAt: now.addingTimeInterval(RenewalPolicy.expirySkew + 1), lastAttempt: nil, now: now))
    }

    @Test func cooldownPreventsRepeatedAttempts() {
        let expired = now.addingTimeInterval(-10)
        #expect(!RenewalPolicy.shouldAttempt(expiresAt: expired, lastAttempt: now.addingTimeInterval(-60), now: now))
        #expect(RenewalPolicy.shouldAttempt(expiresAt: expired,
                                            lastAttempt: now.addingTimeInterval(-RenewalPolicy.cooldown - 1), now: now))
    }

    @Test func unknownExpiryNeverTriggers() {
        #expect(!RenewalPolicy.shouldAttempt(expiresAt: nil, lastAttempt: nil, now: now))
    }

    @Test func aLastAttemptInTheFutureIsTreatedAsStaleClock() {
        // A clock change must not lock renewal out forever.
        #expect(RenewalPolicy.shouldAttempt(expiresAt: now.addingTimeInterval(-10),
                                            lastAttempt: now.addingTimeInterval(3600), now: now))
    }
}
