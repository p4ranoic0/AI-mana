#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

private struct DetailTransport: HTTPTransport {
    let body: String
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private struct Token: AccessTokenSource {
    var plan: String? = nil
    func credentials() async throws -> AccessCredential { AccessCredential(token: "t", accountID: "a", plan: plan) }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let en = Locale(identifier: "en_US")

@Suite struct DetailTests {
    private func claude(_ body: String, plan: String? = nil) async throws -> UsageInfo {
        try await ClaudeProvider(transport: DetailTransport(body: body), tokens: Token(plan: plan), clock: { t0 }).fetchUsage()
    }
    private func codex(_ body: String) async throws -> UsageInfo {
        try await CodexProvider(transport: DetailTransport(body: body), tokens: Token(), clock: { t0 }).fetchUsage()
    }

    // MARK: Claude

    static let claudeBase = #""five_hour":{"utilization":9,"resets_at":"2027-01-15T10:00:00Z"}"#

    @Test func claudeCloudCredits() async throws {
        let body = "{\(Self.claudeBase),\"iguana_necktie\":{\"utilization\":6.5,\"resets_at\":\"2027-02-05T07:59:00+00:00\",\"limit_dollars\":250,\"used_dollars\":16.34,\"remaining_dollars\":233.66,\"locked_reason\":null}}"
        let info = try await claude(body)
        let credit = try #require(info.details.first { $0.kind == .cloudCredits })
        #expect(abs(credit.remaining - 233.66) < 0.001)
        #expect(credit.limit == 250)
        #expect(credit.currency == "USD")
        #expect(credit.expiresAt != nil)
        #expect(credit.summary(locale: en) == "$233.66 left of $250.00")
        #expect(abs((credit.usedFraction ?? 0) - 0.0654) < 0.001)
    }

    @Test func claudeCloudCreditsSkippedWhenLockedExpiredOrInvalid() async throws {
        for fragment in [
            #""iguana_necktie":{"limit_dollars":250,"used_dollars":1,"remaining_dollars":249,"resets_at":"2027-02-05T07:59:00Z","locked_reason":"admin"}"#,
            #""iguana_necktie":{"limit_dollars":250,"used_dollars":1,"remaining_dollars":249,"resets_at":"2020-01-01T00:00:00Z"}"#,
            #""iguana_necktie":{"limit_dollars":0,"used_dollars":0,"remaining_dollars":0}"#,
            #""iguana_necktie":{"limit_dollars":100,"used_dollars":500,"remaining_dollars":-5}"#,
            #""iguana_necktie":"garbage""#,
            #""iguana_necktie":null"#,
        ] {
            let info = try await claude("{\(Self.claudeBase),\(fragment)}")
            #expect(info.details.isEmpty, "fragment: \(fragment)")
            #expect(info.window(.session) != nil)   // a broken extra never breaks the usage itself
        }
    }

    @Test func claudePlanComesFromCredential() async throws {
        let info = try await claude("{\(Self.claudeBase)}", plan: "max")
        #expect(info.plan == "max")
    }

    // MARK: Codex

    static let codexBase = #""plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_at":1800010000,"limit_window_seconds":18000}}"#

    @Test func codexResetCreditsAndBalance() async throws {
        let body = "{\(Self.codexBase),\"credits\":{\"has_credits\":true,\"unlimited\":false,\"balance\":\"12.5\"},\"rate_limit_reset_credits\":{\"available_count\":3,\"applicable_available_count\":1}}"
        let info = try await codex(body)
        let reset = try #require(info.details.first { $0.kind == .resetCredits })
        #expect(reset.remaining == 3)
        #expect(reset.usable == 1)
        #expect(reset.summary(locale: en) == "3 available · 1 usable now")
        let balance = try #require(info.details.first { $0.kind == .creditBalance })
        #expect(balance.remaining == 12.5)
        #expect(balance.summary(locale: en) == "$12.50")
    }

    @Test func codexNoUsableResetCreditsSaysSo() async throws {
        let body = "{\(Self.codexBase),\"rate_limit_reset_credits\":{\"available_count\":3,\"applicable_available_count\":0}}"
        let reset = try #require(try await codex(body).details.first)
        #expect(reset.summary(locale: en) == "3 available · none usable now")
    }

    @Test func codexSkipsEmptyOrUnlimitedOrBrokenExtras() async throws {
        for fragment in [
            #""credits":{"has_credits":false,"unlimited":false,"balance":"0"}"#,
            #""credits":{"has_credits":true,"unlimited":true,"balance":"5"}"#,
            #""credits":"garbage""#,
            #""rate_limit_reset_credits":{"available_count":0,"applicable_available_count":0}"#,
            #""rate_limit_reset_credits":null"#,
        ] {
            let info = try await codex("{\(Self.codexBase),\(fragment)}")
            #expect(info.details.isEmpty, "fragment: \(fragment)")
            #expect(info.window(.session) != nil)
        }
    }

    // MARK: Compatibility

    @Test func snapshotsWithoutDetailsStillDecode() throws {
        let json = #"{"providerID":"claude","providerName":"Claude","windows":[],"plan":null,"lastUpdated":"2027-01-15T10:00:00Z"}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(UsageInfo.self, from: Data(json.utf8))
        #expect(info.details.isEmpty)
    }

    @Test func detailsRoundTrip() throws {
        let info = UsageInfo(providerID: "claude", providerName: "Claude", windows: [], plan: "max", lastUpdated: t0,
                             details: [UsageDetail(kind: .cloudCredits, remaining: 233.66, limit: 250, currency: "USD", expiresAt: t0)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(UsageInfo.self, from: try encoder.encode(info)) == info)
    }

    @Test func captionShowsExpiry() {
        let credit = UsageDetail(kind: .cloudCredits, remaining: 10, limit: 100, currency: "USD",
                                 expiresAt: t0.addingTimeInterval(31 * 86400))
        #expect(credit.caption(now: t0, locale: en) == "Expires in 31d")
        let gone = UsageDetail(kind: .cloudCredits, remaining: 10, limit: 100, currency: "USD", expiresAt: t0.addingTimeInterval(-1))
        #expect(gone.caption(now: t0, locale: en) == "Expired")
        #expect(UsageDetail(kind: .resetCredits, remaining: 3).caption(now: t0) == nil)
    }
}
#endif
