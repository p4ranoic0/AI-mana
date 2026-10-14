import Foundation
import Testing
@testable import AImanaCore

@Suite struct OpenRouterProviderTests {
    /// The documented example response of `GET /api/v1/key`
    /// (https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key).
    static let docsKeyBody = """
    {"data":{"allowed_data_regions":["global","europe","us"],"byok_usage":17.38,"byok_usage_daily":17.38,
     "byok_usage_monthly":17.38,"byok_usage_weekly":17.38,"creator_user_id":"user_2dHFtVWx2n56w6HkM0000000000",
     "expires_at":"2027-12-31T23:59:59Z","free_model_daily_requests":{"limit":50,"remaining":38,"used":12},
     "include_byok_in_limit":false,"is_free_tier":false,"is_management_key":false,"is_provisioning_key":false,
     "label":"sk-or-v1-au7...890","limit":100,"limit_remaining":74.5,"limit_reset":"monthly","organization_id":null,
     "rate_limit":{"interval":"1h","note":"This field is deprecated and safe to ignore.","requests":1000},
     "usage":25.5,"usage_daily":25.5,"usage_monthly":25.5,"usage_weekly":25.5,
     "workspace_id":"0df9e665-d932-5740-b2c7-b52af166bc11"}}
    """

    /// The documented example of `GET /api/v1/credits` (https://openrouter.ai/docs/api/api-reference/credits/get-credits).
    static let docsCreditsBody = #"{"data":{"total_credits":100.5,"total_usage":25.75}}"#

    func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func provider(_ t: MockTransport, now: Date = now) -> OpenRouterProvider {
        OpenRouterProvider(transport: t, tokens: FixedTokens(credential: AccessCredential(token: "sk-or-v1-test")),
                           clock: { now })
    }

    @Test func mapsDocumentedKeyResponse() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 403, body: "")])
        let info = try await provider(t).fetchUsage()
        #expect(info.providerID == "openrouter")
        #expect(info.providerName == "OpenRouter")
        #expect(info.plan == nil)

        let spend = try #require(info.window(.spendLimit))
        #expect(abs(spend.usedPercent - 25.5) < 0.0001)   // 100 - 74.5 of 100
        // `now` is 2027-01-15 08:00 UTC: the monthly limit resets on Feb 1 at midnight UTC.
        #expect(spend.resetsAt == utc(2027, 2, 1))
        #expect(spend.windowMinutes == 31 * 1440)

        let free = try #require(info.window(.freeRequests))   // used today, so it is shown
        #expect(free.usedPercent == 24)
        #expect(free.resetsAt == utc(2027, 1, 16))
        #expect(free.windowMinutes == 1440)
        #expect(info.primary?.kind == .spendLimit)

        #expect(info.details == [UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 25.5)])
    }

    @Test func sendsBearerKeyToTheDocumentedEndpoints() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 200, body: Self.docsCreditsBody)])
        _ = try await provider(t).fetchUsage()
        #expect(t.requests.map(\.url) == [URL(string: "https://openrouter.ai/api/v1/key")!,
                                          URL(string: "https://openrouter.ai/api/v1/credits")!])
        #expect(t.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-test" })
        #expect(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func managementKeyAddsAccountBalance() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 200, body: Self.docsCreditsBody)])
        let info = try await provider(t).fetchUsage()
        let balance = try #require(info.details.first { $0.kind == .creditBalance })
        #expect(balance.remaining == 74.75)
        #expect(balance.limit == 100.5)
        #expect(balance.used == 25.75)
        #expect(balance.currency == "USD")
    }

    @Test func regularKeyAsksForCreditsOnlyOnce() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 403, body: "{}"),
                               .init(status: 200, body: Self.docsKeyBody)])
        let p = provider(t)
        let first = try await p.fetchUsage()
        let second = try await p.fetchUsage()
        #expect(t.requests.count == 3)   // the second refresh skips /credits
        #expect(!first.details.contains { $0.kind == .creditBalance })
        #expect(!second.details.contains { $0.kind == .creditBalance })
    }

    @Test func creditsFailureNeverFailsTheReading() async throws {
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 500, body: "oops")])
        let info = try await provider(t).fetchUsage()
        #expect(info.window(.spendLimit) != nil)
    }

    @Test func unlimitedPaidKeyHasNoSpendLane() throws {
        let body = """
        {"data":{"label":"k","limit":null,"limit_remaining":null,"limit_reset":null,"usage":3.2,"usage_daily":0.4,
         "usage_weekly":1.1,"usage_monthly":2.9,"is_free_tier":false,
         "free_model_daily_requests":{"used":0,"limit":1000,"remaining":1000}}}
        """
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: now)
        #expect(info.window(.spendLimit) == nil)
        // Nothing else to show, so the free-model allowance stands in as the only lane.
        #expect(info.windows.map(\.kind) == [.freeRequests])
        #expect(info.details.first?.used == 2.9)
    }

    @Test func freeModelLaneHiddenForPaidKeysThatDoNotUseIt() throws {
        let body = """
        {"data":{"limit":20,"limit_remaining":15,"limit_reset":"daily","usage":9,"usage_daily":5,"usage_weekly":5,
         "usage_monthly":9,"is_free_tier":false,"free_model_daily_requests":{"used":0,"limit":1000,"remaining":1000}}}
        """
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: now)
        #expect(info.windows.map(\.kind) == [.spendLimit])
        let spend = try #require(info.window(.spendLimit))
        #expect(spend.usedPercent == 25)
        #expect(spend.windowMinutes == 1440)
    }

    /// Replacing an ordinary key with a management key while the app runs must try /credits again.
    @Test func newKeyAsksForCreditsAgain() async throws {
        let store = InMemoryCredentialStore()
        try store.write("sk-or-v1-regular", for: CredentialKey.openRouterAPIKey)
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 403, body: "{}"),
                               .init(status: 200, body: Self.docsKeyBody), .init(status: 200, body: Self.docsCreditsBody)])
        let p = OpenRouterProvider(store: store, transport: t, clock: { now })
        _ = try await p.fetchUsage()
        try store.write("sk-or-v1-management", for: CredentialKey.openRouterAPIKey)
        let second = try await p.fetchUsage()
        #expect(t.requests.count == 4)
        #expect(second.details.contains { $0.kind == .creditBalance })
    }

    @Test func freeRequestsWithoutUsedOrRemainingAddNoLane() throws {
        let body = """
        {"data":{"limit":null,"usage":0,"usage_daily":0,"usage_weekly":0,"usage_monthly":0,"is_free_tier":true,
         "free_model_daily_requests":{"limit":50}}}
        """
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: now)
        #expect(info.window(.freeRequests) == nil)
    }

    @Test func freeTierShowsFreeRequestsAndPlan() throws {
        let body = """
        {"data":{"limit":null,"usage":0,"usage_daily":0,"usage_weekly":0,"usage_monthly":0,"is_free_tier":true,
         "free_model_daily_requests":{"used":0,"limit":50,"remaining":50}}}
        """
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: now)
        #expect(info.plan == "Free")
        #expect(info.window(.freeRequests)?.usedPercent == 0)
    }

    @Test func weeklyLimitResetsOnMondayUTC() throws {
        // Without `limit_remaining`, the period's usage is used instead.
        let body = """
        {"data":{"limit":10,"limit_reset":"weekly","usage":30,"usage_daily":1,"usage_weekly":4,"usage_monthly":9}}
        """
        let friday = utc(2027, 1, 15).addingTimeInterval(10 * 3600)
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: friday)
        let spend = try #require(info.window(.spendLimit))
        #expect(spend.usedPercent == 40)
        #expect(spend.resetsAt == utc(2027, 1, 18))   // Monday
        #expect(spend.windowMinutes == 7 * 1440)
    }

    @Test func neverResettingLimitHasNoResetTime() throws {
        let body = #"{"data":{"limit":50,"limit_remaining":0,"limit_reset":null,"usage":50}}"#
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: nil, now: now)
        let spend = try #require(info.window(.spendLimit))
        #expect(spend.usedPercent == 100)
        #expect(spend.resetsAt == nil)
        #expect(spend.windowMinutes == nil)
    }

    @Test func toleratesOddFieldTypes() throws {
        let body = #"{"data":{"limit":"lots","limit_reset":"hourly","usage_monthly":"x","is_free_tier":"no"}}"#
        let info = try OpenRouterProvider.map(key: Data(body.utf8), credits: Data("nope".utf8), now: now)
        #expect(info.windows.isEmpty)
        #expect(info.details.isEmpty)
    }

    @Test func rejectsNonKeyPayloads() {
        #expect(throws: UsageProviderError.decoding) {
            try OpenRouterProvider.map(key: Data("not json".utf8), credits: nil, now: now)
        }
        #expect(throws: UsageProviderError.decoding) {
            try OpenRouterProvider.map(key: Data(#"{"error":{"code":401,"message":"No auth"}}"#.utf8), credits: nil, now: now)
        }
    }

    @Test func mapsHTTPErrors() async {
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(MockTransport([.init(status: 401, body: #"{"error":{"code":401,"message":"Missing Authentication header"}}"#)])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.server(status: 500)) {
            try await provider(MockTransport([.init(status: 500, body: "")])).fetchUsage()
        }
    }

    @Test func rateLimitIsRemembered() async throws {
        let t = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "120"])])
        let p = provider(t)
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) { try await p.fetchUsage() }
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) { try await p.fetchUsage() }
        #expect(t.requests.count == 1)
    }

    @Test func enabledOnlyWhileAKeyIsSaved() async throws {
        let store = InMemoryCredentialStore()
        let p = OpenRouterProvider(store: store, transport: MockTransport([]), clock: { now })
        #expect(!p.isEnabled)
        try store.write("  ", for: CredentialKey.openRouterAPIKey)
        #expect(!p.isEnabled)
        try store.write("sk-or-v1-abc", for: CredentialKey.openRouterAPIKey)
        #expect(p.isEnabled)
        try store.delete(CredentialKey.openRouterAPIKey)
        #expect(!p.isEnabled)
    }

    @Test func validateRejectsEmptyKeyWithoutNetwork() async {
        let t = MockTransport([])
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await OpenRouterProvider.validate(key: "  \n", transport: t)
        }
        #expect(t.requests.isEmpty)
    }

    @Test func serviceSkipsDisabledProviders() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = SnapshotStore(fileURL: dir.appendingPathComponent("s.json"))
        let store = InMemoryCredentialStore()
        let t = MockTransport([.init(status: 200, body: Self.docsKeyBody), .init(status: 403, body: "")])
        let service = UsageService(providers: [OpenRouterProvider(store: store, transport: t, clock: { now })],
                                   store: snapshot, saveLock: testSaveLock())
        #expect(await service.refresh().isEmpty)
        #expect(await service.cached().isEmpty)
        #expect(t.requests.isEmpty)
        try store.write("sk-or-v1-abc", for: CredentialKey.openRouterAPIKey)
        let states = await service.refresh()
        #expect(states.map(\.providerID) == ["openrouter"])
        #expect(states.first?.usage?.window(.spendLimit) != nil)
    }

    @Test func newKindsRoundTripAndOlderReadersSkipThem() throws {
        for kind in [UsageWindow.Kind.spendLimit, .freeRequests] {
            #expect(UsageWindow.Kind(wireValue: kind.wireValue) == kind)
        }
        #expect(UsageWindow.Kind.spendLimit.wireValue == "spend-limit")
        #expect(UsageWindow.Kind.freeRequests.wireValue == "free-requests")
        // A future lane or balance kind is dropped, the rest of the snapshot survives.
        let json = """
        {"providerID":"openrouter","providerName":"OpenRouter","lastUpdated":0,
         "windows":[{"kind":"spend-limit","usedPercent":25,"windowMinutes":1440},{"kind":"tokens-per-minute","usedPercent":3}],
         "details":[{"kind":"monthlySpend","remaining":0,"used":4},{"kind":"someFutureBalance","remaining":1}]}
        """
        let info = try JSONDecoder().decode(UsageInfo.self, from: Data(json.utf8))
        #expect(info.windows.map(\.kind) == [.spendLimit])
        #expect(info.details.map(\.kind) == [.monthlySpend])
    }

    @Test func spendDetailSummaryUsesCurrency() {
        let detail = UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: 25.5)
        let text = detail.summary(locale: Locale(identifier: "en_US"))
        #expect(text == "$25.50 this month")
        #expect(detail.usedFraction == nil)
    }
}
