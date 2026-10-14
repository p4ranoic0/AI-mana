import Foundation
import Testing
@testable import AImanaCore

@Suite struct BalanceProviderTests {
    /// Documented example of `GET https://api.deepseek.com/user/balance` (https://api-docs.deepseek.com/api/get-user-balance).
    static let deepSeekDocs = """
    {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00",
     "topped_up_balance":"100.00"}]}
    """

    /// Documented example of `GET /v1/users/me/balance` (https://platform.kimi.ai/docs/api/balance).
    static let moonshotDocs = """
    {"code":0,"data":{"available_balance":49.58894,"voucher_balance":46.58893,"cash_balance":3.00001},
     "scode":"0x0","status":true}
    """

    /// Documented example of `GET /auth/management-keys/validation`
    /// (https://docs.x.ai/developers/rest-api-reference/management/auth).
    static let xAIValidationDocs = """
    {"apiKeyId":"b86ba29d-9f47-4b3a-a6ae-e69432d5f0dc","teamId":"65c1e471-205f-4566-9c5a-07198badf4ce",
     "scope":"SCOPE_TEAM","scopeId":"65c1e471-205f-4566-9c5a-07198badf4ce",
     "ownerUserId":"4d52c406-6ec6-4361-9b7c-40dc7e8ff284","createTime":"2025-12-10T23:17:49.460374Z",
     "modifyTime":"2025-12-10T23:17:49.460374Z","name":"test key",
     "acls":["team-token:endpoint:ListApiKeys"],"reactedApiKey":"xai-...r42q"}
    """

    /// Documented example of `GET /v1/billing/teams/{team_id}/prepaid/balance` (https://docs.x.ai/docs/management-api/billing).
    static let xAIBalanceDocs = """
    {"changes":[{"teamId":"65c1e471-205f-4566-9c5a-07198bcdf4ce","changeOrigin":"PURCHASE","topupStatus":"SUCCEEDED",
     "amount":{"val":"-1000"},"invoiceId":"7v7blf6c1G2g34OdI4N5tD1CKCdag4ZYLhn5vTBLIMM=","invoiceNumber":"062-446-653-166",
     "createTime":"2025-02-24T15:28:02.308840Z","paymentProcessor":{"kind":"STRIPE"}}],"total":{"val":"-1000"}}
    """

    func provider(_ descriptor: BalanceDescriptor, _ t: MockTransport, key: String = "sk-test") -> BalanceProvider {
        BalanceProvider(descriptor: descriptor, transport: t,
                        tokens: FixedTokens(credential: AccessCredential(token: key)), clock: { now })
    }

    // MARK: DeepSeek

    @Test func deepSeekMapsDocumentedResponse() async throws {
        let t = MockTransport([.init(status: 200, body: Self.deepSeekDocs)])
        let info = try await provider(.deepSeek, t).fetchUsage()
        #expect(info.providerID == "deepseek")
        #expect(info.providerName == "DeepSeek")
        #expect(info.windows.isEmpty)
        #expect(info.primary == nil)
        #expect(info.plan == nil)
        #expect(info.lastUpdated == now)
        #expect(info.details == [UsageDetail(kind: .creditBalance, remaining: 110, currency: "CNY")])
        #expect(t.requests.map(\.url) == [URL(string: "https://api.deepseek.com/user/balance")!])
        #expect(t.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(t.requests.first?.httpMethod == "GET")
    }

    @Test func deepSeekKeepsEachCurrencyWithoutConverting() throws {
        let body = """
        {"is_available":true,"balance_infos":[
         {"currency":"CNY","total_balance":"12.50","granted_balance":"0.00","topped_up_balance":"12.50"},
         {"currency":"usd","total_balance":3.2,"granted_balance":"0","topped_up_balance":"3.2"},
         {"currency":"CNY","total_balance":"lots"},
         {"total_balance":"1.00"}]}
        """
        let details = try BalanceDecoding.deepSeek(Data(body.utf8))
        #expect(details.map(\.currency) == ["CNY", "USD"])
        #expect(details.map(\.remaining) == [12.5, 3.2])
        #expect(Set(details.map(\.id)).count == 2)   // one row per currency in SwiftUI lists
    }

    @Test func deepSeekEmptyBalanceList() throws {
        let details = try BalanceDecoding.deepSeek(Data(#"{"is_available":true,"balance_infos":[]}"#.utf8))
        #expect(details.isEmpty)
    }

    @Test func deepSeekUnavailableMarksBalanceUnusable() throws {
        let body = """
        {"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.03","granted_balance":"0.00",
         "topped_up_balance":"0.03"}]}
        """
        let detail = try #require(try BalanceDecoding.deepSeek(Data(body.utf8)).first)
        #expect(detail.usable == 0)
        #expect(detail.isExhaustedBalance)
        #expect(detail.caption(now: now, locale: Locale(identifier: "en_US")) == "Too low for API calls")
        let fine = try #require(try BalanceDecoding.deepSeek(Data(Self.deepSeekDocs.utf8)).first)
        #expect(!fine.isExhaustedBalance)
        #expect(fine.caption(now: now) == nil)
    }

    @Test func deepSeekRejectsForeignPayloads() {
        for body in ["not json", #"{"error":{"message":"Authentication Fails","type":"authentication_error"}}"#, "[]"] {
            #expect(throws: UsageProviderError.decoding) { try BalanceDecoding.deepSeek(Data(body.utf8)) }
        }
    }

    // MARK: Moonshot

    @Test func moonshotMapsDocumentedResponseInUSD() async throws {
        let t = MockTransport([.init(status: 200, body: Self.moonshotDocs)])
        let info = try await provider(.moonshot, t).fetchUsage()
        #expect(info.providerID == "moonshot")
        #expect(info.windows.isEmpty)
        #expect(info.details == [UsageDetail(kind: .creditBalance, remaining: 49.58894, currency: "USD")])
        #expect(t.requests.map(\.url) == [URL(string: "https://api.moonshot.ai/v1/users/me/balance")!])
    }

    @Test func moonshotChinaKeyFallsBackToCNHostInCNYAndIsRemembered() async throws {
        let t = MockTransport([.init(status: 401, body: #"{"error":{"type":"invalid_authentication_error"}}"#),
                               .init(status: 200, body: Self.moonshotDocs),
                               .init(status: 200, body: Self.moonshotDocs)])
        let p = provider(.moonshot, t)
        let first = try await p.fetchUsage()
        #expect(first.details.first?.currency == "CNY")
        let second = try await p.fetchUsage()
        #expect(second.details.first?.currency == "CNY")
        #expect(t.requests.map { $0.url?.host } == ["api.moonshot.ai", "api.moonshot.cn", "api.moonshot.cn"])
    }

    @Test func moonshotKeyRejectedByBothHostsIsUnauthenticated() async {
        let t = MockTransport([.init(status: 401, body: ""), .init(status: 401, body: "")])
        await #expect(throws: UsageProviderError.unauthenticated) { try await provider(.moonshot, t).fetchUsage() }
        #expect(t.requests.count == 2)
    }

    @Test func moonshotServerErrorDoesNotTryTheOtherRegion() async {
        let t = MockTransport([.init(status: 503, body: "")])
        await #expect(throws: UsageProviderError.server(status: 503)) { try await provider(.moonshot, t).fetchUsage() }
        #expect(t.requests.count == 1)
    }

    @Test func moonshotNegativeBalanceIsUnusable() throws {
        let body = #"{"code":0,"data":{"available_balance":-1.5,"voucher_balance":0,"cash_balance":-1.5},"status":true}"#
        let detail = try #require(try BalanceDecoding.moonshot(Data(body.utf8), currency: "USD").first)
        #expect(detail.remaining == -1.5)
        #expect(detail.isExhaustedBalance)
        #expect(throws: UsageProviderError.decoding) {
            try BalanceDecoding.moonshot(Data(#"{"code":5,"status":false}"#.utf8), currency: "USD")
        }
    }

    // MARK: xAI

    @Test func xAIReadsTeamThenPrepaidBalance() async throws {
        let t = MockTransport([.init(status: 200, body: Self.xAIValidationDocs), .init(status: 200, body: Self.xAIBalanceDocs),
                               .init(status: 200, body: Self.xAIBalanceDocs)])
        let p = provider(.xAI, t, key: "xai-mgmt")
        let info = try await p.fetchUsage()
        #expect(info.providerID == "xai")
        #expect(info.windows.isEmpty)
        // "-1000" cents of purchases = $10.00 of credit.
        #expect(info.details == [UsageDetail(kind: .creditBalance, remaining: 10, currency: "USD")])
        _ = try await p.fetchUsage()   // the team is remembered
        #expect(t.requests.map(\.url) == [
            URL(string: "https://management-api.x.ai/auth/management-keys/validation")!,
            URL(string: "https://management-api.x.ai/v1/billing/teams/65c1e471-205f-4566-9c5a-07198badf4ce/prepaid/balance")!,
            URL(string: "https://management-api.x.ai/v1/billing/teams/65c1e471-205f-4566-9c5a-07198badf4ce/prepaid/balance")!,
        ])
        #expect(t.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer xai-mgmt" })
    }

    @Test func xAISpentBeyondCreditIsUnusable() throws {
        let detail = try #require(try BalanceDecoding.xAI(Data(#"{"changes":[],"total":{"val":"250"}}"#.utf8)).first)
        #expect(detail.remaining == -2.5)
        #expect(detail.isExhaustedBalance)
        let zero = try #require(try BalanceDecoding.xAI(Data(#"{"total":{"val":"0"}}"#.utf8)).first)
        #expect(zero.remaining == 0)
        #expect(zero.remaining.sign == .plus)
    }

    @Test func xAIInferenceKeyIsRejected() async {
        // An ordinary API key cannot use the Management API.
        let t = MockTransport([.init(status: 401, body: #"{"code":"Unauthenticated"}"#)])
        await #expect(throws: UsageProviderError.unauthenticated) { try await provider(.xAI, t).fetchUsage() }
    }

    @Test func xAIBalanceForbiddenForgetsTheTeam() async {
        let t = MockTransport([.init(status: 200, body: Self.xAIValidationDocs), .init(status: 403, body: ""),
                               .init(status: 200, body: Self.xAIValidationDocs), .init(status: 200, body: Self.xAIBalanceDocs)])
        let p = provider(.xAI, t)
        await #expect(throws: UsageProviderError.unauthenticated) { try await p.fetchUsage() }
        let info = try? await p.fetchUsage()
        #expect(info?.details.first?.remaining == 10)
        #expect(t.requests.count == 4)   // looked the team up again
    }

    @Test func xAIRejectsForeignPayloads() async {
        #expect(BalanceDecoding.xAITeamID(Data("{}".utf8)) == nil)
        #expect(throws: UsageProviderError.decoding) { try BalanceDecoding.xAI(Data(#"{"changes":[]}"#.utf8)) }
        let t = MockTransport([.init(status: 200, body: #"{"name":"no team"}"#)])
        await #expect(throws: UsageProviderError.decoding) { try await provider(.xAI, t).fetchUsage() }
        #expect(t.requests.count == 1)
    }

    // MARK: Shared behaviour

    @Test(arguments: BalanceDescriptor.all.map(\.id))
    func mapsHTTPErrors(id: String) async throws {
        let descriptor = try #require(BalanceDescriptor.descriptor(id: id))
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(descriptor, MockTransport([.init(status: 403, body: ""), .init(status: 403, body: "")])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.server(status: 500)) {
            try await provider(descriptor, MockTransport([.init(status: 500, body: "")])).fetchUsage()
        }
        let t = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "90"])])
        let p = provider(descriptor, t)
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(90))) { try await p.fetchUsage() }
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(90))) { try await p.fetchUsage() }
        #expect(t.requests.count == 1)   // the backoff is remembered
    }

    @Test(arguments: BalanceDescriptor.all.map(\.id))
    func enabledOnlyWhileAKeyIsSaved(id: String) throws {
        let descriptor = try #require(BalanceDescriptor.descriptor(id: id))
        let store = InMemoryCredentialStore()
        let p = BalanceProvider(descriptor: descriptor, store: store, transport: MockTransport([]), clock: { now })
        #expect(p.id == id)
        #expect(!p.isEnabled)
        try store.write(" \n", for: descriptor.credentialKey)
        #expect(!p.isEnabled)
        try store.write("sk-abc", for: descriptor.credentialKey)
        #expect(p.isEnabled)
        try store.delete(descriptor.credentialKey)
        #expect(!p.isEnabled)
    }

    @Test func eachProviderHasItsOwnKeychainEntry() {
        let keys = BalanceDescriptor.all.map(\.credentialKey) + [CredentialKey.openRouterAPIKey]
        #expect(Set(keys).count == keys.count)
        #expect(BalanceDescriptor.all.map(\.id) == ["deepseek", "moonshot", "xai"])
    }

    @Test func validateRejectsEmptyKeyWithoutNetwork() async {
        let t = MockTransport([])
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await BalanceProvider.validate(.deepSeek, key: "   ", transport: t)
        }
        #expect(t.requests.isEmpty)
    }

    @Test func validateSendsTrimmedKey() async throws {
        let t = MockTransport([.init(status: 200, body: Self.deepSeekDocs)])
        _ = try await BalanceProvider.validate(.deepSeek, key: "  sk-new\n", transport: t)
        #expect(t.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-new")
    }

    @Test func serviceSkipsProvidersWithoutAKey() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = SnapshotStore(fileURL: dir.appendingPathComponent("s.json"))
        let store = InMemoryCredentialStore()
        let t = MockTransport([.init(status: 200, body: Self.deepSeekDocs)])
        let service = UsageService(providers: BalanceDescriptor.all.map {
            BalanceProvider(descriptor: $0, store: store, transport: t, clock: { now })
        }, store: snapshot, saveLock: testSaveLock())
        #expect(await service.refresh().isEmpty)
        #expect(t.requests.isEmpty)
        try store.write("sk-abc", for: CredentialKey.deepSeekAPIKey)
        let states = await service.refresh()
        #expect(states.map(\.providerID) == ["deepseek"])
        #expect(states.first?.usage?.details.first?.currency == "CNY")
        // A balance-only reading survives the snapshot round trip with no lanes.
        let saved = try #require(snapshot.load().first)
        #expect(saved.windows.isEmpty)
        #expect(saved.details == [UsageDetail(kind: .creditBalance, remaining: 110, currency: "CNY")])
    }

    @Test func balanceSummaryUsesTheReportedCurrency() {
        let en = Locale(identifier: "en_US")
        let cny = UsageDetail(kind: .creditBalance, remaining: 110, currency: "CNY")
        #expect(cny.summary(locale: en).contains("110.00"))
        #expect(cny.summary(locale: en).contains("CN¥"))
        let usd = UsageDetail(kind: .creditBalance, remaining: 10, currency: "USD")
        #expect(usd.summary(locale: en) == "$10.00")
    }
}
