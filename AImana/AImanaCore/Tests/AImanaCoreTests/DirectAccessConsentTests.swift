import Foundation
import Testing
@testable import AImanaCore

@Suite struct DirectAccessConsentTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "direct-access-consent-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func offByDefault() {
        withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            for provider in DirectProvider.allCases {
                #expect(!consent.isGranted(provider))
                #expect(consent.consentedAt(provider) == nil)
            }
        }
    }

    @Test func grantThenRevoke() {
        withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            consent.grant(.codex, now: now)
            #expect(consent.isGranted(.codex))
            #expect(consent.consentedAt(.codex) == now)
            #expect(defaults.double(forKey: "directAccess.codex.consentedAt") == now.timeIntervalSince1970)
            #expect(defaults.integer(forKey: "directAccess.codex.noticeVersion") == 1)

            let reloaded = DirectAccessConsent(defaults: defaults)
            #expect(reloaded.isGranted(.codex))
            #expect(reloaded.consentedAt(.codex) == now)
            reloaded.revoke(.codex)
            #expect(!consent.isGranted(.codex))
            #expect(consent.consentedAt(.codex) == nil)
            #expect(defaults.object(forKey: "directAccess.codex.noticeVersion") == nil)
        }
    }

    @Test func olderNoticeVersionIsNotConsent() {
        withDefaults { defaults in
            defaults.set(0, forKey: "directAccess.claude.noticeVersion")
            defaults.set(1_700_000_000.0, forKey: "directAccess.claude.consentedAt")
            #expect(!DirectAccessConsent(defaults: defaults).isGranted(.claude))
        }
    }

    @Test func providersAreIndependent() {
        withDefaults { defaults in
            let consent = DirectAccessConsent(defaults: defaults)
            consent.grant(.claude)
            #expect(consent.isGranted(.claude))
            #expect(!consent.isGranted(.codex))
            #expect(consent.consentedAt(.codex) == nil)

            consent.grant(.codex)
            consent.revoke(.claude)
            #expect(!consent.isGranted(.claude))
            #expect(consent.consentedAt(.claude) == nil)
            #expect(consent.isGranted(.codex))
            #expect(consent.consentedAt(.codex) != nil)
        }
    }
}
