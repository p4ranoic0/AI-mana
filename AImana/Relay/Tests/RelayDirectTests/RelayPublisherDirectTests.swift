import AImanaCore
import AImanaSignIn
import Foundation
import Testing
@testable import RelayKit

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let status: Int
    private let body: String
    private(set) var calls = 0

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { calls += 1 }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct FakeTokens: AccessTokenSource {
    func credentials() async throws -> AccessCredential { AccessCredential(token: "test-token", accountID: "acct") }
}

private let t0 = Date(timeIntervalSince1970: 1_787_700_000)

private let claudeEndpointBody = #"{"five_hour":{"utilization":61.0,"resets_at":"2026-08-26T03:00:00Z"},"seven_day":{"utilization":30,"resets_at":"2026-08-30T00:00:00Z"}}"#

private func codexLine(_ stamp: String, session: Double) -> String {
    #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":\#(session),"window_minutes":300,"resets_at":1787703892},"secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1788272683},"plan_type":"plus"}}}"#
}

private struct Env {
    let root: URL
    let paths: RelayPaths
    var output: URL { root.appendingPathComponent("iCloud/AImana/usage-relay.json") }

    init() throws {
        root = try makeTempDir()
        paths = RelayPaths(home: root, environment: [:])
    }

    func writeStatusline(_ text: String) throws {
        try FileManager.default.createDirectory(at: paths.claudeStatuslineFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: paths.claudeStatuslineFile)
    }

    @discardableResult
    func writeCodexLog(_ name: String, lines: [String], modified: Date) throws -> URL {
        let dir = paths.codexSessionRoots[0].appendingPathComponent("2026/08/25")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    func publisher(claude: MockTransport? = nil, codex: MockTransport? = nil) -> RelayPublisher {
        RelayPublisher(paths: paths, endpoints: { id, _ in
            switch id {
            case "claude": claude.map { ClaudeProvider(transport: $0, tokens: FakeTokens(), clock: { t0 }) }
            case "codex": codex.map { CodexProvider(transport: $0, tokens: FakeTokens(), clock: { t0 }) }
            default: nil
            }
        }, clock: { t0 })
    }

    func options(claude: Bool = false, codex: Bool = false) -> RelayOptions {
        RelayOptions(output: output, endpointProviderIDs: Set(([claude ? "claude" : nil, codex ? "codex" : nil]).compactMap { $0 }), includeCosts: false,
                     allowPricingDownload: false)
    }

    func published() throws -> RelayEnvelope { try RelayEnvelope.decode(Data(contentsOf: output)) }
}

@Suite struct RelayPublisherTests {
    @Test func localSourcesByDefault() async throws {
        let env = try Env()
        try env.writeStatusline(#"{"capturedAt":1787699000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1787710000}}}"#)
        try env.writeCodexLog("a.jsonl", lines: [codexLine("2026-08-25T23:00:00Z", session: 50)], modified: t0)
        let claude = MockTransport(status: 200, body: claudeEndpointBody)
        _ = try await env.publisher(claude: claude).publish(env.options())

        let envelope = try env.published()
        #expect(envelope.version == 1)
        let c = try #require(envelope.entries.first { $0.providerID == "claude" })
        #expect(c.source == .statusline)
        #expect(c.usage?.window(.session)?.usedPercent == 23.5)
        #expect(c.usage?.lastUpdated == Date(timeIntervalSince1970: 1_787_699_000))
        let x = try #require(envelope.entries.first { $0.providerID == "codex" })
        #expect(x.source == .logs)
        #expect(x.usage?.window(.session)?.usedPercent == 50)
        #expect(claude.calls == 0) // endpoints are never called unless opted in
        // History lives in the state directory, stamped at the readings' own times.
        let history = HistoryStore.load(from: env.paths.historyFile)
        #expect(history.first { $0.providerID == "claude" }?.points.last?.t == Date(timeIntervalSince1970: 1_787_699_000))
    }

    @Test func endpointOptInWinsAndFallsBack() async throws {
        let env = try Env()
        try env.writeStatusline(#"{"capturedAt":1787699000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1787710000}}}"#)
        try env.writeCodexLog("a.jsonl", lines: [codexLine("2026-08-25T23:00:00Z", session: 50)], modified: t0)
        let claude = MockTransport(status: 200, body: claudeEndpointBody)
        let codex = MockTransport(status: 401, body: "")
        _ = try await env.publisher(claude: claude, codex: codex).publish(env.options(claude: true, codex: true))

        let envelope = try env.published()
        let c = try #require(envelope.entries.first { $0.providerID == "claude" })
        #expect(c.source == .endpoint)
        #expect(c.usage?.window(.session)?.usedPercent == 61)
        let x = try #require(envelope.entries.first { $0.providerID == "codex" })
        #expect(x.source == .logs) // endpoint failed → local logs
        #expect(x.usage?.window(.session)?.usedPercent == 50)
        #expect(claude.calls == 1 && codex.calls == 1)
    }

    @Test func reportKeepsAnEndpointFailureTheLocalSourceHid() async throws {
        let env = try Env()
        try env.writeStatusline(#"{"capturedAt":1787699000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1787710000}}}"#)
        let report = try await env.publisher(claude: MockTransport(status: 401, body: "")).publish(env.options(claude: true))
        #expect(report.envelope.entries.first { $0.providerID == "claude" }?.error == nil) // statusline won
        #expect(report.endpoints == ["claude": .failure(.unauthenticated)])
        #expect(report.macLogins(providerIDs: ["claude", "codex"]) == ["claude": .expired, "codex": .signedOut])
    }

    @Test func nothingAvailablePublishesErrorsNotZeros() async throws {
        let env = try Env()
        _ = try await env.publisher().publish(env.options())
        let envelope = try env.published()
        #expect(envelope.entries.map(\.error) == [.relayUnavailable, .relayUnavailable])
        #expect(envelope.entries.allSatisfy { $0.usage == nil })

        let failing = MockTransport(status: 401, body: "")
        _ = try await env.publisher(claude: failing).publish(env.options(claude: true))
        #expect(try env.published().entries.first?.error == .unauthenticated)
    }

    @Test func republishingAnOldCaptureKeepsItsTimeAndAddsNoHistory() async throws {
        let env = try Env()
        try env.writeStatusline(#"{"capturedAt":1787699000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1787710000}}}"#)
        let first = RelayPublisher(paths: env.paths, endpoints: { _, _ in nil }, clock: { t0 })
        let later = RelayPublisher(paths: env.paths, endpoints: { _, _ in nil }, clock: { t0.addingTimeInterval(1800) })
        _ = try await first.publish(env.options())
        _ = try await later.publish(env.options())
        let envelope = try env.published()
        #expect(envelope.generatedAt == t0.addingTimeInterval(1800))
        #expect(envelope.entries.first?.usage?.lastUpdated == Date(timeIntervalSince1970: 1_787_699_000))
        #expect(HistoryStore.load(from: env.paths.historyFile).first { $0.providerID == "claude" }?.points.count == 1)
    }

    @Test func envelopeHasNoCredentialsOrPaths() async throws {
        let env = try Env()
        try env.writeCodexLog("a.jsonl", lines: [codexLine("2026-08-25T23:00:00Z", session: 5)], modified: t0)
        _ = try await env.publisher(claude: MockTransport(status: 200, body: claudeEndpointBody)).publish(env.options(claude: true))
        let text = try String(contentsOf: env.output, encoding: .utf8)
        #expect(!text.contains("test-token"))
        #expect(!text.contains(env.root.path))
    }
}

@Suite struct CodexLogReaderTests {
    @Test func newestEventAcrossFilesWithMtimeCutoff() throws {
        let env = try Env()
        try env.writeCodexLog("old.jsonl", lines: [codexLine("2026-08-25T10:00:00Z", session: 10)], modified: t0.addingTimeInterval(-86400))
        try env.writeCodexLog("new.jsonl", lines: [codexLine("2026-08-25T22:00:00Z", session: 70),
                                                   #"{"timestamp":"2026-08-25T22:01:00Z","type":"response_item","payload":{"type":"message"}}"#],
                              modified: t0)
        // Touched recently but its last rate-limit event is older than new.jsonl's.
        try env.writeCodexLog("touched.jsonl", lines: [codexLine("2026-08-25T21:00:00Z", session: 33)], modified: t0.addingTimeInterval(-10))
        let info = try CodexLogReader.read(roots: env.paths.codexSessionRoots).get()
        #expect(info.window(.session)?.usedPercent == 70)
        #expect(info.lastUpdated == ISO8601DateFormatter().date(from: "2026-08-25T22:00:00Z"))
    }

    @Test func readsTailsInGrowingChunksWithinCaps() throws {
        let env = try Env()
        let filler = #"{"timestamp":"2026-08-25T22:30:00Z","type":"response_item","payload":{"type":"x","pad":"\#(String(repeating: "z", count: 1000))"}}"#
        let lines = [codexLine("2026-08-25T22:00:00Z", session: 42)] + Array(repeating: filler, count: 300)
        let url = try env.writeCodexLog("big.jsonl", lines: lines, modified: t0)
        let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size > 250_000)

        let found = CodexLogReader.latest(in: url, size: size, limits: .init(firstChunk: 16 << 10), budget: 8 << 20)
        #expect(found.0?.window(.session)?.usedPercent == 42)

        let capped = CodexLogReader.latest(in: url, size: size, limits: .init(maxBytesPerFile: 100_000, firstChunk: 16 << 10),
                                           budget: 8 << 20)
        #expect(capped.0 == nil)
        #expect(capped.1 <= 16_384 + 32_768 + 65_536 + 100_000)
    }

    @Test func noLogsIsUnavailable() throws {
        let env = try Env()
        #expect(throws: UsageProviderError.relayUnavailable) { try CodexLogReader.read(roots: env.paths.codexSessionRoots).get() }
    }
}

@Suite struct ClaudeStatuslineReaderTests {
    @Test func missingFileIsUnavailable() throws {
        let env = try Env()
        #expect(throws: UsageProviderError.relayUnavailable) {
            try ClaudeStatuslineReader.read(file: env.paths.claudeStatuslineFile, now: t0).get()
        }
    }
}
