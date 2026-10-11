import Foundation
import Testing
@testable import AImanaCore

private let claudeLine = #"{"type":"assistant","timestamp":"2026-10-04T21:22:16.806Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5-5","role":"assistant","content":[{"type":"text","text":"SECRET CONVERSATION TEXT"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":24572,"cache_read_input_tokens":25166,"output_tokens":531}}}"#

@Suite struct CostParsingTests {
    // MARK: Claude

    @Test func claudeEventUsesUsageFieldsAndNeverTheContent() throws {
        let event = try #require(ClaudeLogParser.event(from: Data(claudeLine.utf8)))
        #expect(event.model == "claude-sonnet-5-5")
        #expect(event.key == "msg_1:req_1")
        #expect(event.tokens == TokenUsage(input: 2, output: 531, cacheRead: 25166, cacheWrite: 24572))
        let expected = ISO8601DateFormatter.fractional.date(from: "2026-10-04T21:22:16.806Z")!
        #expect(event.timestamp == expected)
    }

    @Test func claudeSkipsNonUsageSyntheticAndEmptyLines() {
        let user = #"{"type":"user","timestamp":"2026-10-04T21:22:16Z","message":{"role":"user","content":"hi"}}"#
        let synthetic = #"{"type":"assistant","timestamp":"2026-10-04T21:22:16Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":5,"output_tokens":5}}}"#
        let zero = #"{"type":"assistant","timestamp":"2026-10-04T21:22:16Z","message":{"id":"m","model":"claude-opus-5","usage":{"input_tokens":0,"output_tokens":0}}}"#
        for line in [user, synthetic, zero, "not json", ""] {
            #expect(ClaudeLogParser.event(from: Data(line.utf8)) == nil, "line: \(line.prefix(40))")
        }
    }

    // MARK: Codex

    private func codexLines(_ lines: [String]) -> [CostEvent] {
        var parser = CodexLogParser()
        return lines.compactMap { parser.consume(Data($0.utf8)) }
    }

    private func turn(_ model: String) -> String { #"{"type":"turn_context","timestamp":"2026-10-04T10:00:00Z","payload":{"model":"\#(model)"}}"# }

    private func count(_ ts: String, total: (Int, Int, Int), last: (Int, Int, Int)) -> String {
        // (input, cached, output)
        #"{"type":"event_msg","timestamp":"\#(ts)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total.0),"cached_input_tokens":\#(total.1),"cache_write_input_tokens":0,"output_tokens":\#(total.2),"total_tokens":\#(total.0 + total.2)},"last_token_usage":{"input_tokens":\#(last.0),"cached_input_tokens":\#(last.1),"cache_write_input_tokens":0,"output_tokens":\#(last.2),"total_tokens":\#(last.0 + last.2)}}}}"#
    }

    @Test func codexUsesCumulativeDeltasAndNormalizesCachedInput() throws {
        let events = codexLines([
            turn("gpt-5.6-sol"),
            count("2026-10-04T10:00:01Z", total: (1000, 400, 50), last: (1000, 400, 50)),
            count("2026-10-04T10:00:02Z", total: (3000, 1500, 120), last: (2000, 1100, 70)),
        ])
        #expect(events.count == 2)
        // OpenAI `input_tokens` includes cached input: billable input = input - cached.
        #expect(events[0].tokens == TokenUsage(input: 600, output: 50, cacheRead: 400, cacheWrite: 0))
        #expect(events[1].tokens == TokenUsage(input: 900, output: 70, cacheRead: 1100, cacheWrite: 0))
        #expect(events.allSatisfy { $0.model == "gpt-5.6-sol" })
    }

    @Test func codexIgnoresRepeatedSnapshots() {
        let line = count("2026-10-04T10:00:01Z", total: (1000, 400, 50), last: (1000, 400, 50))
        #expect(codexLines([turn("gpt-6-sol"), line, line, line]).count == 1)
    }

    @Test func codexCounterResetFallsBackToLastUsage() throws {
        let events = codexLines([
            turn("gpt-6-sol"),
            count("2026-10-04T10:00:01Z", total: (5000, 0, 100), last: (5000, 0, 100)),
            count("2026-10-04T10:00:02Z", total: (800, 0, 20), last: (800, 0, 20)),   // compaction/new thread
        ])
        #expect(events.count == 2)
        #expect(events[1].tokens.input == 800)
    }

    @Test func codexForkStartUsesLastNotInheritedTotal() throws {
        // First event of a forked rollout carries the parent's cumulative total; only `last` is new work.
        let events = codexLines([turn("gpt-6-sol"),
                                 count("2026-10-04T10:00:01Z", total: (90_000, 50_000, 900), last: (2000, 1000, 40))])
        #expect(events.count == 1)
        #expect(events[0].tokens == TokenUsage(input: 1000, output: 40, cacheRead: 1000, cacheWrite: 0))
    }

    @Test func codexModelFollowsLatestTurnContext() {
        let events = codexLines([
            turn("gpt-5.6-luna"), count("2026-10-04T10:00:01Z", total: (100, 0, 10), last: (100, 0, 10)),
            turn("gpt-6-sol"), count("2026-10-04T10:00:09Z", total: (300, 0, 30), last: (200, 0, 20)),
        ])
        #expect(events.map(\.model) == ["gpt-5.6-luna", "gpt-6-sol"])
    }

    @Test func codexUnknownModelWhenNoTurnContext() {
        let events = codexLines([count("2026-10-04T10:00:01Z", total: (100, 0, 10), last: (100, 0, 10))])
        #expect(events.first?.model == "unknown")
    }

    @Test func codexIgnoresOtherLines() {
        let other = #"{"type":"response_item","timestamp":"2026-10-04T10:00:01Z","payload":{"type":"message","content":"SECRET"}}"#
        let nullInfo = #"{"type":"event_msg","timestamp":"2026-10-04T10:00:01Z","payload":{"type":"token_count","info":null}}"#
        #expect(codexLines([other, nullInfo, "garbage"]).isEmpty)
    }
}
