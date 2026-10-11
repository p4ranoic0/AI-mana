import Foundation
import Testing
@testable import AImanaCore

@Suite struct CopilotProviderTests {
    /// The documented example of `GET /users/{username}/settings/billing/ai_credit/usage`
    /// (`billing-ai-credit-usage-report-user` in github/rest-api-description;
    /// https://docs.github.com/en/rest/billing/usage#get-billing-ai-credit-usage-report-for-a-user).
    static let docsAICreditBody = """
    {"timePeriod":{"year":2025},"user":"monalisa","usageItems":[{"product":"Copilot AI Credits","sku":"AI Credit",
     "model":"GPT-5","unitType":"ai-credits","pricePerUnit":0.01,"grossQuantity":100,"grossAmount":1.0,
     "discountQuantity":0,"discountAmount":0.0,"netQuantity":100,"netAmount":1.0}]}
    """

    /// The documented example of `GET /users/{username}/settings/billing/premium_request/usage`
    /// (`billing-premium-request-usage-report-user`).
    static let docsPremiumBody = """
    {"timePeriod":{"year":2025},"user":"monalisa","usageItems":[{"product":"Copilot","sku":"Copilot Premium Request",
     "model":"GPT-5","unitType":"requests","pricePerUnit":0.04,"grossQuantity":100,"grossAmount":4.0,
     "discountQuantity":0,"discountAmount":0.0,"netQuantity":100,"netAmount":4.0}]}
    """

    /// Part of the documented `GET /user` example (https://docs.github.com/en/rest/users/users#get-the-authenticated-user).
    static let docsUserBody = #"{"login":"octocat","id":1,"type":"User","name":"monalisa octocat"}"#

    /// A month mostly covered by the included credits: $12.40 used, $10.15 included, $2.25 billed.
    static let overBody = """
    {"timePeriod":{"year":2027,"month":1},"user":"octocat","usageItems":[
     {"product":"Copilot AI Credits","sku":"AI Credit","model":"Claude Sonnet 4.6","unitType":"ai-credits",
      "pricePerUnit":0.01,"grossQuantity":840,"grossAmount":8.40,"discountQuantity":840,"discountAmount":8.40,
      "netQuantity":0,"netAmount":0},
     {"product":"Copilot AI Credits","sku":"AI Credit","model":"GPT-5","unitType":"ai-credits",
      "pricePerUnit":0.01,"grossQuantity":400,"grossAmount":4.00,"discountQuantity":175,"discountAmount":1.75,
      "netQuantity":225,"netAmount":2.25}]}
    """

    func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// 2027-01-15 08:00 UTC (`now` in ProviderTests).
    var jan15: Date { now }

    func provider(_ t: MockTransport, plan: CopilotPlan = .pro, custom: Double? = nil,
                  at date: Date = now) -> CopilotProvider {
        CopilotProvider(transport: t, tokens: FixedTokens(credential: AccessCredential(token: "github_pat_test")),
                        allowance: { CopilotAllowance(plan: plan, customUSD: custom) }, clock: { date })
    }

    @Test func mapsDocumentedAICreditReportAgainstPlan() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody), .init(status: 200, body: Self.docsAICreditBody)])
        let info = try await provider(t).fetchUsage()
        #expect(info.providerID == "copilot")
        #expect(info.providerName == "GitHub Copilot")
        #expect(info.plan == "Pro")
        let lane = try #require(info.window(.spendLimit))
        #expect(abs(lane.usedPercent - 1.0 / 15 * 100) < 0.0001)   // $1 of Pro's 1,500 credits ($15)
        #expect(lane.resetsAt == utc(2027, 2, 1))
        #expect(lane.windowMinutes == 31 * 1440)
        #expect(info.details.first == UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 1.0))
        #expect(info.details.last?.kind == .extraUsage)   // the example's netAmount is billed
    }

    @Test func sendsDocumentedRequests() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody), .init(status: 200, body: Self.docsAICreditBody)])
        _ = try await provider(t).fetchUsage()
        #expect(t.requests.map(\.url?.absoluteString) == [
            "https://api.github.com/user",
            "https://api.github.com/users/octocat/settings/billing/ai_credit/usage?year=2027&month=1",
        ])
        for request in t.requests {
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer github_pat_test")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
            #expect(request.value(forHTTPHeaderField: "User-Agent") != nil)
        }
    }

    @Test func loginIsReadOncePerToken() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody), .init(status: 200, body: Self.docsAICreditBody),
                               .init(status: 200, body: Self.docsAICreditBody)])
        let p = provider(t)
        _ = try await p.fetchUsage()
        _ = try await p.fetchUsage()
        #expect(t.requests.count == 3)
        #expect(t.requests.filter { $0.url?.path == "/user" }.count == 1)
    }

    @Test func sumsItemsAndReportsOverage() throws {
        let info = try CopilotProvider.map(report: Data(Self.overBody.utf8), unit: .aiCredits,
                                           allowance: CopilotAllowance(plan: .business), now: jan15)
        let lane = try #require(info.window(.spendLimit))
        #expect(abs(lane.usedPercent - 12.40 / 19 * 100) < 0.0001)
        #expect(info.plan == "Business")
        let spend = try #require(info.details.first { $0.kind == .monthlySpend })
        #expect(abs((spend.used ?? 0) - 12.40) < 0.0001)
        let extra = try #require(info.details.first { $0.kind == .extraUsage })
        #expect(abs((extra.used ?? 0) - 2.25) < 0.0001)
    }

    @Test func planAllowancesFollowGitHubsTables() {
        #expect(CopilotAllowance(plan: .pro).includedUSD == 15)
        #expect(CopilotAllowance(plan: .proPlus).includedUSD == 70)
        #expect(CopilotAllowance(plan: .max).includedUSD == 200)
        #expect(CopilotAllowance(plan: .business).includedUSD == 19)
        #expect(CopilotAllowance(plan: .enterprise).includedUSD == 39)
        #expect(CopilotAllowance(plan: .custom, customUSD: 25).includedUSD == 25)
        #expect(CopilotAllowance(plan: .custom, customUSD: nil).includedUSD == nil)
        #expect(CopilotAllowance(plan: .custom, customUSD: -3).includedUSD == nil)
    }

    @Test func overAllowanceKeepsRawPercent() throws {
        let info = try CopilotProvider.map(report: Data(Self.overBody.utf8), unit: .aiCredits,
                                           allowance: CopilotAllowance(plan: .custom, customUSD: 10), now: jan15)
        let lane = try #require(info.window(.spendLimit))
        #expect(abs(lane.usedPercent - 124) < 0.0001)
        #expect(lane.displayUsedPercent == 100)
        #expect(info.plan == nil)
    }

    @Test func customWithoutAmountShowsSpendOnly() throws {
        let info = try CopilotProvider.map(report: Data(Self.overBody.utf8), unit: .aiCredits,
                                           allowance: CopilotAllowance(plan: .custom), now: jan15)
        #expect(info.windows.isEmpty)
        #expect(info.details.contains { $0.kind == .monthlySpend })
    }

    @Test func emptyMonthIsZero() throws {
        let body = #"{"timePeriod":{"year":2027,"month":1},"user":"octocat","usageItems":[]}"#
        let info = try CopilotProvider.map(report: Data(body.utf8), unit: .aiCredits,
                                           allowance: CopilotAllowance(plan: .proPlus), now: jan15)
        #expect(info.window(.spendLimit)?.usedPercent == 0)
        #expect(info.details == [UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 0)])
    }

    @Test func monthBoundsAreUTC() {
        let lastSecond = utc(2027, 3, 1).addingTimeInterval(-1)
        let month = CopilotProvider.utcMonth(containing: lastSecond)
        #expect(month.year == 2027 && month.month == 2)
        #expect(month.start == utc(2027, 2, 1))
        #expect(month.end == utc(2027, 3, 1))
    }

    @Test func foreignShapeIsDecodingError() {
        #expect(throws: UsageProviderError.decoding) {
            try CopilotProvider.map(report: Data(#"{"message":"hi"}"#.utf8), unit: .aiCredits,
                                    allowance: CopilotAllowance(plan: .pro), now: jan15)
        }
    }

    @Test func aiCredit404FallsBackToPremiumRequests() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody), .init(status: 404, body: #"{"message":"Not Found"}"#),
                               .init(status: 200, body: Self.docsPremiumBody)])
        let info = try await provider(t, plan: .proPlus).fetchUsage()
        #expect(t.requests.last?.url?.path == "/users/octocat/settings/billing/premium_request/usage")
        let lane = try #require(info.window(.spendLimit))
        #expect(abs(lane.usedPercent - 100.0 / 1500 * 100) < 0.0001)   // 100 of Pro+'s 1,500 requests
        #expect(lane.resetsAt == utc(2027, 2, 1))
    }

    @Test func premiumRequestsWithoutDocumentedAllowanceHaveNoLane() throws {
        let info = try CopilotProvider.map(report: Data(Self.docsPremiumBody.utf8), unit: .premiumRequests,
                                           allowance: CopilotAllowance(plan: .business), now: jan15)
        #expect(info.windows.isEmpty)
        #expect(info.details.first?.used == 4.0)
    }

    @Test func bothReportsMissingIsUnsupported() async {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody), .init(status: 404, body: "{}"),
                               .init(status: 404, body: "{}")])
        await #expect(throws: UsageProviderError.decoding) { try await provider(t).fetchUsage() }
    }

    @Test func rejectedTokenIsUnauthenticated() async {
        let t = MockTransport([.init(status: 401, body: #"{"message":"Bad credentials"}"#)])
        await #expect(throws: UsageProviderError.unauthenticated) { try await provider(t).fetchUsage() }
    }

    @Test func missingPermissionIsUnauthenticatedAndForgetsLogin() async {
        let t = MockTransport([.init(status: 200, body: Self.docsUserBody),
                               .init(status: 403, body: #"{"message":"Resource not accessible by personal access token"}"#),
                               .init(status: 200, body: Self.docsUserBody), .init(status: 200, body: Self.docsAICreditBody)])
        let p = provider(t)
        await #expect(throws: UsageProviderError.unauthenticated) { try await p.fetchUsage() }
        _ = try? await p.fetchUsage()
        #expect(t.requests.filter { $0.url?.path == "/user" }.count == 2)
    }

    @Test func rateLimitIsRememberedUntilReset() async throws {
        let reset = jan15.addingTimeInterval(600)
        let t = MockTransport([.init(status: 403, body: #"{"message":"API rate limit exceeded"}"#,
                                     headers: ["x-ratelimit-remaining": "0",
                                               "x-ratelimit-reset": String(Int(reset.timeIntervalSince1970))])])
        let p = provider(t)
        await #expect(throws: UsageProviderError.rateLimited(until: reset)) { try await p.fetchUsage() }
        await #expect(throws: UsageProviderError.rateLimited(until: reset)) { try await p.fetchUsage() }
        #expect(t.requests.count == 1)
    }

    @Test func http429IsRateLimited() async {
        let t = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "30"])])
        await #expect(throws: UsageProviderError.rateLimited(until: jan15.addingTimeInterval(30))) {
            try await provider(t).fetchUsage()
        }
    }

    @Test func loginIsPathEscaped() {
        let url = CopilotProvider.reportURL(login: "a/b", report: "ai_credit", year: 2027, month: 2)
        #expect(url.absoluteString == "https://api.github.com/users/a%2Fb/settings/billing/ai_credit/usage?year=2027&month=2")
    }

    @Test func preferencesRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "copilot-test-\(UUID().uuidString)"))
        #expect(CopilotPreferences.allowance(defaults: defaults) == CopilotAllowance(plan: .pro))
        CopilotPreferences.setPlan(.custom, defaults: defaults)
        CopilotPreferences.setCustomUSD(42.5, defaults: defaults)
        #expect(CopilotPreferences.allowance(defaults: defaults) == CopilotAllowance(plan: .custom, customUSD: 42.5))
        CopilotPreferences.setCustomUSD(0, defaults: defaults)
        #expect(CopilotPreferences.allowance(defaults: defaults).customUSD == nil)
    }

    @Test func customTitleIsLocalizedAndProductNamesAreNot() {
        let en = Locale(identifier: "en")
        #expect(CopilotPlan.custom.title(locale: en) == "Custom amount")
        #expect(CopilotPlan.proPlus.title(locale: en) == "Copilot Pro+")
    }

    @Test func noTokenIsUnauthenticated() async {
        let p = CopilotProvider(transport: MockTransport([]), tokens: FixedTokens(credential: nil))
        await #expect(throws: UsageProviderError.unauthenticated) { try await p.fetchUsage() }
    }
}
