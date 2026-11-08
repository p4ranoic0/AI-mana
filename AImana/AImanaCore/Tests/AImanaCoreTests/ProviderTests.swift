#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

// MARK: - Claude

@Suite struct ClaudeProviderTests {
    static let okBody = """
    {"five_hour":{"utilization":18.0,"resets_at":"2027-01-15T10:00:00.123Z"},
     "seven_day":{"utilization":42,"resets_at":"2027-01-20T00:00:00Z"},
     "seven_day_sonnet":{"utilization":7.5,"resets_at":"2027-01-20T00:00:00Z"},
     "seven_day_opus":{"utilization":3,"resets_at":"2027-01-20T00:00:00Z"}}
    """

    func provider(_ t: MockTransport, tokens: FixedTokens = FixedTokens()) -> ClaudeProvider {
        ClaudeProvider(transport: t, tokens: tokens, clock: { now })
    }

    @Test func mapsAllLanesByKind() async throws {
        let info = try await provider(MockTransport([.init(status: 200, body: Self.okBody)])).fetchUsage()
        #expect(info.providerID == "claude")
        #expect(info.window(.session)?.usedPercent == 18)
        #expect(info.window(.session)?.windowMinutes == 300)
        #expect(info.window(.session)?.remainingPercent == 82)
        #expect(info.window(.weekly)?.usedPercent == 42)
        #expect(info.window(.weekly)?.windowMinutes == 10080)
        // both model lanes are kept (CodexBar would drop one)
        #expect(info.window(.model("Sonnet"))?.usedPercent == 7.5)
        #expect(info.window(.model("Opus"))?.usedPercent == 3)
        #expect(info.window(.session)?.resetsAt != nil)   // fractional-second ISO date parsed
        #expect(info.lastUpdated == now)
    }

    @Test func parsesMicrosecondOffsetDatesAndScopedLimits() async throws {
        // Shape observed from the live endpoint (synthetic values).
        let body = """
        {"five_hour":{"utilization":9.0,"resets_at":"2027-01-15T10:20:00.677592+00:00"},
         "seven_day":{"utilization":35.0,"resets_at":"2027-01-20T17:00:00.677646+00:00"},
         "seven_day_sonnet":null,
         "limits":[
           {"kind":"session","percent":9,"resets_at":"2027-01-15T10:20:00.677592+00:00","scope":null},
           {"kind":"weekly_scoped","percent":4,"resets_at":"2027-01-20T17:00:00+00:00",
            "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}]}
        """
        let info = try await provider(MockTransport([.init(status: 200, body: body)])).fetchUsage()
        let expected = ISO8601DateFormatter().date(from: "2027-01-15T10:20:00Z")!
        #expect(abs(info.window(.session)!.resetsAt!.timeIntervalSince(expected)) < 1)
        #expect(info.window(.model("Fable"))?.usedPercent == 4)
        #expect(info.windows.count == 3)   // session, weekly, Fable (unscoped limits not duplicated)
    }

    @Test func absentSessionIsAbsentNotZero() async throws {
        let body = #"{"five_hour":null,"seven_day":{"utilization":10,"resets_at":"2027-01-20T00:00:00Z"}}"#
        let info = try await provider(MockTransport([.init(status: 200, body: body)])).fetchUsage()
        #expect(info.window(.session) == nil)
        #expect(info.primary?.kind == .weekly)
    }

    @Test func emptyPayloadIsDecodingError() async {
        await #expect(throws: UsageProviderError.decoding) {
            try await provider(MockTransport([.init(status: 200, body: "{}")])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.decoding) {
            try await provider(MockTransport([.init(status: 200, body: "not json")])).fetchUsage()
        }
    }

    @Test func sendsExpectedHeaders() async throws {
        let t = MockTransport([.init(status: 200, body: Self.okBody)])
        _ = try await provider(t).fetchUsage()
        let r = t.requests[0]
        #expect(r.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(r.httpMethod == "GET")
    }

    @Test func retriesWithoutOptionalQueryOn400() async throws {
        let t = MockTransport([.init(status: 400, body: "bad"), .init(status: 200, body: Self.okBody)])
        _ = try await provider(t).fetchUsage()
        #expect(t.requests.count == 2)
        #expect(t.requests[1].url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    }

    @Test func unauthorizedAndMissingScope() async {
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(MockTransport([.init(status: 401, body: "")])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(MockTransport([.init(status: 403, body: "missing scope user:profile")])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(MockTransport([]), tokens: FixedTokens(credential: nil)).fetchUsage()
        }
    }

    @Test func rateLimitHonoursRetryAfterAndBlocksRepeatCalls() async {
        let t = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "120"])])
        let p = provider(t)
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) {
            try await p.fetchUsage()
        }
        // second call inside the window must not hit the network
        await #expect(throws: UsageProviderError.rateLimited(until: now.addingTimeInterval(120))) {
            try await p.fetchUsage()
        }
        #expect(t.requests.count == 1)
    }

    @Test func serverErrorCarriesStatus() async {
        await #expect(throws: UsageProviderError.server(status: 503)) {
            try await provider(MockTransport([.init(status: 503, body: "")])).fetchUsage()
        }
    }
}

// MARK: - Codex

@Suite struct CodexProviderTests {
    static let okBody = """
    {"plan_type":"plus","account_id":"acct",
     "rate_limit":{
       "primary_window":{"used_percent":33,"reset_at":1800010000,"limit_window_seconds":18000},
       "secondary_window":{"used_percent":12,"reset_at":1800500000,"limit_window_seconds":604800}}}
    """

    func provider(_ t: MockTransport) -> CodexProvider {
        CodexProvider(transport: t, tokens: FixedTokens(), clock: { now })
    }

    @Test func mapsSessionAndWeekly() async throws {
        let info = try await provider(MockTransport([.init(status: 200, body: Self.okBody)])).fetchUsage()
        #expect(info.providerID == "codex")
        #expect(info.plan == "plus")
        #expect(info.window(.session)?.usedPercent == 33)
        #expect(info.window(.session)?.windowMinutes == 300)
        #expect(info.window(.session)?.resetsAt == Date(timeIntervalSince1970: 1_800_010_000))
        #expect(info.window(.weekly)?.windowMinutes == 10080)
        #expect(info.window(.weekly)?.remainingPercent == 88)
    }

    @Test func swappedWindowsAreNormalizedByDuration() async throws {
        let body = """
        {"rate_limit":{
         "primary_window":{"used_percent":12,"reset_at":1800500000,"limit_window_seconds":604800},
         "secondary_window":{"used_percent":33,"reset_at":1800010000,"limit_window_seconds":18000}}}
        """
        let info = try await provider(MockTransport([.init(status: 200, body: body)])).fetchUsage()
        #expect(info.window(.session)?.usedPercent == 33)
        #expect(info.window(.weekly)?.usedPercent == 12)
    }

    @Test func singleWeeklyWindowLeavesNoSession() async throws {
        let body = #"{"rate_limit":{"primary_window":{"used_percent":5,"reset_at":1800500000,"limit_window_seconds":604800}}}"#
        let info = try await provider(MockTransport([.init(status: 200, body: body)])).fetchUsage()
        #expect(info.window(.session) == nil)
        #expect(info.window(.weekly)?.usedPercent == 5)
    }

    @Test func missingRateLimitIsDecodingError() async {
        await #expect(throws: UsageProviderError.decoding) {
            try await provider(MockTransport([.init(status: 200, body: #"{"plan_type":"free"}"#)])).fetchUsage()
        }
    }

    @Test func sendsExpectedHeaders() async throws {
        let t = MockTransport([.init(status: 200, body: Self.okBody)])
        _ = try await provider(t).fetchUsage()
        let r = t.requests[0]
        #expect(r.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(r.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")
    }

    @Test func statusMapping() async {
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await provider(MockTransport([.init(status: 401, body: "")])).fetchUsage()
        }
        await #expect(throws: UsageProviderError.server(status: 500)) {
            try await provider(MockTransport([.init(status: 500, body: "")])).fetchUsage()
        }
    }
}
#endif
