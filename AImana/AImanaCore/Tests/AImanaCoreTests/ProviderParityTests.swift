#if canImport(AImanaSignIn)
import CryptoKit
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

/// The same provider responses the Kotlin core maps (`Android/core/.../providers/*Test.kt`): both must agree.
private struct ParityWindow: Decodable { let kind: String; let usedPercent: Double; let windowMinutes: Int?; let resetsAt: String? }
private struct ParityDetail: Decodable {
    let kind: String; let remaining: Double; let limit: Double?; let currency: String?; let used: Double?; let usable: Double?
    let expiresAt: String?
}
private struct ParityExpected: Decodable { let windows: [ParityWindow]; let details: [ParityDetail]; let plan: String? }
private struct ProviderFixture: Decodable { let now: String; let plan: String?; let expected: ParityExpected }

private func load(_ name: String) throws -> (fixture: ProviderFixture, response: Data) {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../Fixtures/parity/\(name)").standardizedFileURL
    let data = try Data(contentsOf: url)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let response = try JSONSerialization.data(withJSONObject: try #require(object["response"]))
    return (try JSONDecoder().decode(ProviderFixture.self, from: data), response)
}

private func expectMatches(_ usage: UsageInfo, _ expected: ParityExpected) {
    #expect(usage.windows.map(\.kind.wireValue) == expected.windows.map(\.kind))
    for (window, want) in zip(usage.windows, expected.windows) {
        #expect(window.usedPercent == want.usedPercent)
        #expect(window.windowMinutes == want.windowMinutes)
        #expect(window.resetsAt == ISODate.parse(want.resetsAt))
    }
    #expect(usage.details.map(\.kind.rawValue) == expected.details.map(\.kind))
    for (detail, want) in zip(usage.details, expected.details) {
        #expect(detail.remaining == want.remaining)
        #expect(detail.limit == want.limit)
        #expect(detail.currency == want.currency)
        #expect(detail.used == want.used)
        #expect(detail.usable == want.usable)
        #expect(detail.expiresAt == ISODate.parse(want.expiresAt))
    }
}

private struct OAuthVectors: Decodable {
    struct Pair: Decodable { let verifier: String; let challenge: String }
    struct Pasted: Decodable { let raw: String; let state: String; let code: String? }
    let pkce: [Pair]
    let pastedCode: [Pasted]
}

@Suite struct ProviderParityTests {
    @Test func oauthVectorsMatch() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Fixtures/parity/oauth-vectors.json").standardizedFileURL
        let vectors = try JSONDecoder().decode(OAuthVectors.self, from: Data(contentsOf: url))
        for pair in vectors.pkce {
            #expect(ClaudeOAuth.base64URL(Data(SHA256.hash(data: Data(pair.verifier.utf8)))) == pair.challenge)
        }
        for case_ in vectors.pastedCode {
            #expect((try? ClaudeOAuth.parsePastedCode(case_.raw, expectedState: case_.state)) == case_.code)
        }
    }

    @Test func claudeMapperMatchesParityFixture() throws {
        let (fixture, response) = try load("claude-usage-response.json")
        let now = try #require(ISODate.parse(fixture.now))
        let usage = try ClaudeProvider.map(response, now: now, plan: fixture.plan)
        expectMatches(usage, fixture.expected)
        #expect(usage.plan == fixture.plan)
    }

    /// The five API balances: the same responses `BalanceClientsTest`, `OpenRouterClientTest` and `CopilotClientTest` map.
    @Test func balanceFixturesMatch() throws {
        func extra(_ name: String, _ key: String) throws -> Any? {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../Fixtures/parity/balances/\(name)").standardizedFileURL
            return (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?[key]
        }
        func data(_ value: Any?) throws -> Data { try JSONSerialization.data(withJSONObject: try #require(value)) }

        for (name, decode) in [("deepseek.json", { try BalanceDecoding.deepSeek($0) }),
                               ("xai.json", { try BalanceDecoding.xAI($0) })] as [(String, (Data) throws -> [UsageDetail])] {
            let (fixture, response) = try load("balances/\(name)")
            #expect(fixture.expected.windows.isEmpty)
            expectMatches(UsageInfo(providerID: "x", providerName: "x", windows: [], plan: nil,
                                    lastUpdated: Date(), details: try decode(response)), fixture.expected)
        }
        let (moonshot, moonshotResponse) = try load("balances/moonshot.json")
        let currency = try #require(try extra("moonshot.json", "currency") as? String)
        expectMatches(UsageInfo(providerID: "moonshot", providerName: "x", windows: [], plan: nil, lastUpdated: Date(),
                                details: try BalanceDecoding.moonshot(moonshotResponse, currency: currency)), moonshot.expected)
        #expect(BalanceDecoding.xAITeamID(try data(try extra("xai.json", "validation")))
                == (try extra("xai.json", "expectedTeamId") as? String))

        let (openRouter, keyResponse) = try load("balances/openrouter.json")
        let openRouterUsage = try OpenRouterProvider.map(key: keyResponse, credits: try data(try extra("openrouter.json", "credits")),
                                                         now: try #require(ISODate.parse(openRouter.now)))
        expectMatches(openRouterUsage, openRouter.expected)
        #expect(openRouterUsage.plan == openRouter.expected.plan)

        let (copilot, report) = try load("balances/copilot.json")
        let planName = try extra("copilot.json", "allowancePlan") as? String
        let plan = try #require(planName.flatMap(CopilotPlan.init(rawValue:)))
        let copilotUsage = try CopilotProvider.map(report: report, unit: .aiCredits, allowance: CopilotAllowance(plan: plan),
                                                   now: try #require(ISODate.parse(copilot.now)))
        expectMatches(copilotUsage, copilot.expected)
        #expect(copilotUsage.plan == copilot.expected.plan)
    }

    @Test func codexMapperMatchesParityFixture() throws {
        let (fixture, response) = try load("codex-usage-response.json")
        let usage = try CodexProvider.map(response, now: try #require(ISODate.parse(fixture.now)))
        expectMatches(usage, fixture.expected)
        #expect(usage.plan == fixture.expected.plan)
    }
}
#endif
