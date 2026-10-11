import Foundation
import Testing
@testable import AImanaCore

// Fixture provenance:
// - Claude: shape from https://code.claude.com/docs/en/statusline (`rate_limits.five_hour.used_percentage`, `resets_at`
//   epoch seconds) wrapped as AImana's statusline script writes it (`capturedAt` + `rate_limits`). Values are made up.
// - Codex: line structure copied key-for-key from a real `~/.codex/sessions` rollout `token_count` event (keys only were
//   inspected); the numbers are the sample quoted in the plan review, not the user's data.

private let fixedNow = Date(timeIntervalSince1970: 1_787_700_000)

private func claudeFile(capturedAt: String = "1787699000", limits: String) -> Data {
    Data(#"{"capturedAt":\#(capturedAt),"rate_limits":\#(limits)}"#.utf8)
}

private func codexLine(timestamp: String = "2026-08-25T23:20:00.000Z", payloadType: String = "token_count",
                       limits: String) -> String {
    #"{"timestamp":"\#(timestamp)","ordinal":12,"type":"event_msg","payload":{"type":"\#(payloadType)","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":90,"reasoning_output_tokens":10,"total_tokens":1290},"last_token_usage":{"input_tokens":300,"cached_input_tokens":200,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":320},"model_context_window":258400},"rate_limits":\#(limits)}}"#
}

private let realCodexLimits = #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":93.0,"window_minutes":300,"resets_at":1787703892},"secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1788272683},"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}"#

@Suite struct ClaudeStatuslineSourceTests {
    @Test func mapsBothWindows() throws {
        let data = claudeFile(limits: #"{"five_hour":{"used_percentage":23.5,"resets_at":1787710000},"seven_day":{"used_percentage":41,"resets_at":1788000000}}"#)
        let info = try ClaudeStatuslineSource.usage(from: data, now: fixedNow)
        #expect(info.providerID == "claude")
        #expect(info.window(.session)?.usedPercent == 23.5)
        #expect(info.window(.session)?.windowMinutes == 300)
        #expect(info.window(.session)?.resetsAt == Date(timeIntervalSince1970: 1_787_710_000))
        #expect(info.window(.weekly)?.usedPercent == 41)
        #expect(info.window(.weekly)?.windowMinutes == 10080)
    }

    @Test func lastUpdatedIsCaptureTimeNotReadTime() throws {
        let data = claudeFile(capturedAt: "1787690000", limits: #"{"five_hour":{"used_percentage":5,"resets_at":1787710000}}"#)
        let first = try ClaudeStatuslineSource.usage(from: data, now: fixedNow)
        let muchLater = try ClaudeStatuslineSource.usage(from: data, now: fixedNow.addingTimeInterval(900))
        #expect(first.lastUpdated == Date(timeIntervalSince1970: 1_787_690_000))
        #expect(muchLater.lastUpdated == first.lastUpdated)
    }

    @Test func acceptsISOCapturedAt() throws {
        let data = claudeFile(capturedAt: #""2026-08-25T22:00:00Z""#, limits: #"{"seven_day":{"used_percentage":12,"resets_at":1788000000}}"#)
        let info = try ClaudeStatuslineSource.usage(from: data, now: fixedNow)
        #expect(info.lastUpdated == ISO8601DateFormatter().date(from: "2026-08-25T22:00:00Z"))
        #expect(info.window(.session) == nil)
        #expect(info.window(.weekly)?.usedPercent == 12)
    }

    @Test func futureCaptureIsClampedToNow() throws {
        let data = claudeFile(capturedAt: "1787800000", limits: #"{"five_hour":{"used_percentage":5,"resets_at":1787810000}}"#)
        #expect(try ClaudeStatuslineSource.usage(from: data, now: fixedNow).lastUpdated == fixedNow)
    }

    @Test func pastResetIsOutdatedNeverZero() throws {
        let data = claudeFile(limits: #"{"five_hour":{"used_percentage":88,"resets_at":1787600000},"seven_day":{"used_percentage":40,"resets_at":1788000000}}"#)
        let info = try ClaudeStatuslineSource.usage(from: data, now: fixedNow)
        let session = try #require(info.window(.session))
        #expect(session.usedPercent == 88)
        #expect(session.isOutdated(now: fixedNow))
        #expect(info.window(.weekly)?.isOutdated(now: fixedNow) == false)
    }

    @Test func missingRateLimitsIsUnavailableNotZero() {
        let noLimits = Data(#"{"capturedAt":1787699000}"#.utf8)
        #expect(throws: UsageProviderError.relayUnavailable) { try ClaudeStatuslineSource.usage(from: noLimits, now: fixedNow) }
        let emptyLimits = claudeFile(limits: "{}")
        #expect(throws: UsageProviderError.relayUnavailable) { try ClaudeStatuslineSource.usage(from: emptyLimits, now: fixedNow) }
        let nullWindows = claudeFile(limits: #"{"five_hour":null,"seven_day":{"used_percentage":null}}"#)
        #expect(throws: UsageProviderError.relayUnavailable) { try ClaudeStatuslineSource.usage(from: nullWindows, now: fixedNow) }
    }

    @Test func corruptFileIsDecodingError() {
        #expect(throws: UsageProviderError.decoding) { try ClaudeStatuslineSource.usage(from: Data("{oops".utf8), now: fixedNow) }
        let noStamp = Data(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1787710000}}}"#.utf8)
        #expect(throws: UsageProviderError.decoding) { try ClaudeStatuslineSource.usage(from: noStamp, now: fixedNow) }
    }

    @Test func missingStampFallsBackToFileDate() throws {
        let noStamp = Data(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1787710000}}}"#.utf8)
        let mtime = Date(timeIntervalSince1970: 1_787_650_000)
        #expect(try ClaudeStatuslineSource.usage(from: noStamp, fallbackCapturedAt: mtime, now: fixedNow).lastUpdated == mtime)
    }

    @Test func millisecondEpochsAreRecognised() throws {
        let data = claudeFile(capturedAt: "1787699000000", limits: #"{"five_hour":{"used_percentage":2,"resets_at":1787710000000}}"#)
        let info = try ClaudeStatuslineSource.usage(from: data, now: fixedNow)
        #expect(info.lastUpdated == Date(timeIntervalSince1970: 1_787_699_000))
        #expect(info.window(.session)?.resetsAt == Date(timeIntervalSince1970: 1_787_710_000))
    }
}

@Suite struct CodexLogSourceTests {
    @Test func mapsRealShapedEvent() throws {
        let info = try #require(CodexLogSource.usage(fromLine: Data(codexLine(limits: realCodexLimits).utf8)))
        #expect(info.providerID == "codex")
        #expect(info.plan == "plus")
        #expect(info.lastUpdated == ISO8601DateFormatter.parseLoose("2026-08-25T23:20:00.000Z"))
        #expect(info.window(.session)?.usedPercent == 93)
        #expect(info.window(.session)?.resetsAt == Date(timeIntervalSince1970: 1_787_703_892))
        #expect(info.window(.weekly)?.usedPercent == 28)
        #expect(info.window(.weekly)?.windowMinutes == 10080)
        #expect(info.details.isEmpty)
    }

    @Test func swappedSlotsAreClassifiedByDuration() throws {
        let limits = #"{"limit_id":"codex","primary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1788272683},"secondary":{"used_percent":93.0,"window_minutes":300,"resets_at":1787703892}}"#
        let info = try #require(CodexLogSource.usage(fromLine: Data(codexLine(limits: limits).utf8)))
        #expect(info.window(.session)?.usedPercent == 93)
        #expect(info.window(.weekly)?.usedPercent == 28)
    }

    @Test func singleWindowAndUnknownDurations() throws {
        let weeklyOnly = #"{"limit_id":"codex","primary":null,"secondary":{"used_percent":96.0,"window_minutes":10080,"resets_at":1788272683}}"#
        let info = try #require(CodexLogSource.usage(fromLine: Data(codexLine(limits: weeklyOnly).utf8)))
        #expect(info.window(.session) == nil)
        #expect(info.window(.weekly)?.usedPercent == 96)

        let odd = #"{"primary":{"used_percent":50.0,"window_minutes":20160,"resets_at":1788272683},"secondary":{"used_percent":10.0,"window_minutes":60,"resets_at":1787703892}}"#
        let oddInfo = try #require(CodexLogSource.usage(fromLine: Data(codexLine(limits: odd).utf8)))
        #expect(oddInfo.window(.session)?.windowMinutes == 60)
        #expect(oddInfo.window(.weekly)?.windowMinutes == 20160)
    }

    @Test func ignoresEventsWithoutWindowsOrForOtherLimits() {
        let premium = #"{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"plus"}"#
        #expect(CodexLogSource.usage(fromLine: Data(codexLine(limits: premium).utf8)) == nil)
        let otherModel = #"{"limit_id":"codex_other","primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1787703892}}"#
        #expect(CodexLogSource.usage(fromLine: Data(codexLine(limits: otherModel).utf8)) == nil)
        #expect(CodexLogSource.usage(fromLine: Data(codexLine(limits: "null").utf8)) == nil)
        #expect(CodexLogSource.usage(fromLine: Data(codexLine(payloadType: "agent_message", limits: realCodexLimits).utf8)) == nil)
        #expect(CodexLogSource.usage(fromLine: Data(#"{"type":"event_msg","payload":{"type":"token_count"}}"#.utf8)) == nil)
        #expect(CodexLogSource.usage(fromLine: Data("not json \"rate_limits\"".utf8)) == nil)
    }

    @Test func creditBalanceBecomesDetail() throws {
        let limits = #"{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1787703892},"credits":{"has_credits":true,"unlimited":false,"balance":"12.5"}}"#
        let info = try #require(CodexLogSource.usage(fromLine: Data(codexLine(limits: limits).utf8)))
        #expect(info.details.first?.kind == .creditBalance)
        #expect(info.details.first?.remaining == 12.5)
    }

    @Test func tailChunkPicksLastEventAndSkipsPartialFirstLine() throws {
        let older = codexLine(timestamp: "2026-08-25T20:00:00.000Z", limits: realCodexLimits.replacingOccurrences(of: "93.0", with: "40.0"))
        let newer = codexLine(timestamp: "2026-08-25T23:20:00.000Z", limits: realCodexLimits)
        let unrelated = #"{"timestamp":"2026-08-25T23:21:00.000Z","type":"response_item","payload":{"type":"message"}}"#
        let file = [older, newer, unrelated, ""].joined(separator: "\n")
        let info = try #require(CodexLogSource.latestUsage(inJSONL: Data(file.utf8), startsMidLine: false))
        #expect(info.window(.session)?.usedPercent == 93)

        // A chunk that starts in the middle of `newer` must not decode that fragment.
        let cut = String(file.dropFirst(older.count + 1 + 40))
        #expect(CodexLogSource.latestUsage(inJSONL: Data(cut.utf8), startsMidLine: true) == nil)
        let cutOlder = String(file.dropFirst(20))
        #expect(CodexLogSource.latestUsage(inJSONL: Data(cutOlder.utf8), startsMidLine: true)?.window(.session)?.usedPercent == 93)
    }

    @Test func newestAcrossFiles() throws {
        let a = try #require(CodexLogSource.usage(fromLine: Data(codexLine(timestamp: "2026-08-25T10:00:00Z", limits: realCodexLimits).utf8)))
        let b = try #require(CodexLogSource.usage(fromLine: Data(codexLine(timestamp: "2026-08-25T12:00:00Z", limits: realCodexLimits).utf8)))
        #expect(CodexLogSource.newest([a, b])?.lastUpdated == b.lastUpdated)
        #expect(CodexLogSource.newest([]) == nil)
    }
}

@Suite struct RelaySourcePolicyTests {
    private func info(_ id: String, used: Double) -> UsageInfo {
        UsageInfo(providerID: id, providerName: id,
                  windows: [UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300, resetsAt: nil)],
                  plan: nil, lastUpdated: fixedNow)
    }

    @Test func endpointOffUsesLocal() {
        let entry = RelaySourcePolicy.entry(providerID: "claude", endpoint: nil, local: .success(info("claude", used: 10)),
                                            localSource: .statusline)
        #expect(entry.source == .statusline)
        #expect(entry.usage?.windows.first?.usedPercent == 10)
        #expect(entry.error == nil)
    }

    @Test func endpointOffLocalFails() {
        let entry = RelaySourcePolicy.entry(providerID: "codex", endpoint: nil, local: .failure(.relayUnavailable),
                                            localSource: .logs)
        #expect(entry.usage == nil)
        #expect(entry.error == .relayUnavailable)
        #expect(entry.source == .logs)
    }

    @Test func endpointOnAndSucceededWins() {
        let entry = RelaySourcePolicy.entry(providerID: "claude", endpoint: .success(info("claude", used: 70)),
                                            local: .success(info("claude", used: 10)), localSource: .statusline)
        #expect(entry.source == .endpoint)
        #expect(entry.usage?.windows.first?.usedPercent == 70)
    }

    @Test func endpointOnButFailedFallsBackToLocal() {
        let entry = RelaySourcePolicy.entry(providerID: "codex", endpoint: .failure(.unauthenticated),
                                            local: .success(info("codex", used: 33)), localSource: .logs)
        #expect(entry.source == .logs)
        #expect(entry.usage?.windows.first?.usedPercent == 33)
        #expect(entry.error == nil)
    }

    @Test func bothFailReportsEndpointError() {
        let entry = RelaySourcePolicy.entry(providerID: "claude", endpoint: .failure(.unauthenticated),
                                            local: .failure(.relayUnavailable), localSource: .statusline)
        #expect(entry.usage == nil)
        #expect(entry.error == .unauthenticated)
        #expect(entry.source == .endpoint)
    }
}
