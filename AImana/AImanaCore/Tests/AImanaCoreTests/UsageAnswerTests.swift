import Foundation
import Testing
@testable import AImanaCore

/// The Siri / Shortcuts answer. English literals only with an explicit `en` locale (the Mac runs in Spanish).
@Suite struct UsageAnswerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let en = Locale(identifier: "en")

    private func window(_ kind: UsageWindow.Kind, used: Double, minutes: Int, resetsIn: TimeInterval) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: used, windowMinutes: minutes, resetsAt: now.addingTimeInterval(resetsIn))
    }

    /// Session 22 % with 3 h left of 5 (comfortable); weekly 60 % after 3 of 7 days (fast: 100 % in exactly 2 days).
    private var claude: UsageInfo {
        UsageInfo(providerID: "claude", providerName: "Claude Code",
                  windows: [window(.session, used: 22, minutes: 300, resetsIn: 3 * 3600),
                            window(.weekly, used: 60, minutes: 10080, resetsIn: 4 * 86400),
                            window(.model("Sonnet"), used: 5, minutes: 10080, resetsIn: 4 * 86400)],
                  plan: "Max", lastUpdated: now.addingTimeInterval(-60))
    }

    /// Weekly 12 % after 3 of 7 days: comfortable, 88 % left over 4 days = 22 % per day.
    private var codex: UsageInfo {
        UsageInfo(providerID: "codex", providerName: "OpenAI Codex",
                  windows: [window(.weekly, used: 12, minutes: 10080, resetsIn: 4 * 86400)],
                  plan: "Pro", lastUpdated: now.addingTimeInterval(-60))
    }

    @Test func usedModeSaysUsedResetAndFastPace() {
        let text = UsageAnswer.text(items: [claude, codex], providerIDs: ["claude"], mode: .used, now: now, locale: en)
        #expect(text == "Claude Code: Session 22% used, resets in 3h; Weekly 60% used, fast pace, runs out in 2d.")
    }

    @Test func remainingModeSaysLeftWithDailyBudget() {
        let text = UsageAnswer.text(items: [claude, codex], providerIDs: ["codex"], mode: .remaining, now: now, locale: en)
        #expect(text == "OpenAI Codex: Weekly 88% left, about 22% per day, resets in 4d.")
    }

    @Test func allProvidersOneLineEach() {
        let text = UsageAnswer.text(items: [codex, claude], providerIDs: ["claude", "codex"], mode: .used,
                                    now: now, locale: en)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Claude Code:"))
        #expect(lines[1].hasPrefix("OpenAI Codex:"))
    }

    @Test func staleReadingSaysItsAge() {
        let old = UsageInfo(providerID: "codex", providerName: "OpenAI Codex", windows: codex.windows,
                            plan: nil, lastUpdated: now.addingTimeInterval(-2 * 3600))
        let text = UsageAnswer.line(for: old, mode: .used, now: now, locale: en)
        #expect(text.hasSuffix(" Last updated 2h ago."))
    }

    @Test func outdatedLaneIsNotReadAsCurrent() {
        let info = UsageInfo(providerID: "claude", providerName: "Claude Code",
                             windows: [window(.session, used: 90, minutes: 300, resetsIn: -60)],
                             plan: nil, lastUpdated: now.addingTimeInterval(-60))
        #expect(UsageAnswer.line(for: info, mode: .used, now: now, locale: en)
                == "Claude Code: Session has reset since the last reading.")
    }

    @Test func missingDataIsSaid() {
        #expect(UsageAnswer.text(items: [], providerIDs: ["claude", "codex"], mode: .used, now: now, locale: en)
                == "No usage yet. Open AI·mana to load it.")
        let text = UsageAnswer.text(items: [claude], providerIDs: ["claude", "codex"], mode: .used, now: now, locale: en)
        #expect(text.hasSuffix("\nOpenAI Codex: no data yet."))
    }

    @Test func refreshNeededWhenMissingOrOlderThanFiveMinutes() {
        #expect(!UsageAnswer.needsRefresh(items: [claude, codex], providerIDs: ["claude", "codex"], now: now))
        #expect(UsageAnswer.needsRefresh(items: [claude], providerIDs: ["claude", "codex"], now: now))
        #expect(UsageAnswer.needsRefresh(items: [claude], providerIDs: ["claude"], now: now.addingTimeInterval(5 * 60)))
    }

    @Test func onDemandIgnoresIntervalButNotDoubleTaps() {
        let snapshot = [claude]
        let later = now.addingTimeInterval(10 * 60)
        #expect(RefreshSchedule.isDueOnDemand(snapshot: snapshot, providerIDs: ["claude"], maxAge: 300,
                                              lastAttempt: nil, now: later))
        #expect(!RefreshSchedule.isDueOnDemand(snapshot: snapshot, providerIDs: ["claude"], maxAge: 300,
                                               lastAttempt: later.addingTimeInterval(-5), now: later))
        #expect(!RefreshSchedule.isDueOnDemand(snapshot: snapshot, providerIDs: ["claude"], maxAge: 300,
                                               lastAttempt: nil, now: now))
        #expect(!RefreshSchedule.isDueOnDemand(snapshot: snapshot, providerIDs: [], maxAge: 0,
                                               lastAttempt: nil, now: later))
    }

    @Test func urgentSessionIsTheFullestOne() throws {
        let busy = UsageInfo(providerID: "codex", providerName: "OpenAI Codex",
                             windows: [window(.session, used: 70, minutes: 300, resetsIn: 3600)],
                             plan: nil, lastUpdated: now)
        let pick = try #require(UsageAnswer.urgentSession(items: [claude, busy], mode: .used, now: now))
        #expect(pick.info.providerID == "codex")
        #expect(pick.window.usedPercent == 70)
        // Codex reports only a weekly lane: it stands in as the headline.
        let fallback = try #require(UsageAnswer.urgentSession(items: [codex], mode: .remaining, now: now))
        #expect(fallback.window.kind == .weekly)
        #expect(UsageAnswer.urgentSession(items: [], mode: .used, now: now) == nil)
        #expect(UsageAnswer.compact(pick.info, window: pick.window, mode: .used, locale: en) == "OpenAI Codex 70% used")
        #expect(UsageAnswer.compact(pick.info, window: pick.window, mode: .remaining, locale: en) == "OpenAI Codex 30% left")
    }
}
