import Foundation
import Testing
@testable import AImanaCore

@Suite struct ModelTests {
    @Test func remainingIsClampedAtZero() {
        let w = UsageWindow(kind: .session, usedPercent: 130, windowMinutes: 300, resetsAt: nil)
        #expect(w.remainingPercent == 0)
        #expect(w.displayUsedPercent == 100)
    }

    @Test func remainingFromUsed() {
        let w = UsageWindow(kind: .session, usedPercent: 18, windowMinutes: 300, resetsAt: nil)
        #expect(w.remainingPercent == 82)
    }

    @Test func primaryIsChosenByKindNotPosition() {
        let session = UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: nil)
        let weekly = UsageWindow(kind: .weekly, usedPercent: 50, windowMinutes: 10080, resetsAt: nil)
        let info = UsageInfo(providerID: "claude", providerName: "Claude Code",
                             windows: [weekly, session], plan: nil, lastUpdated: .distantPast)
        #expect(info.primary == session)
        #expect(info.window(.weekly) == weekly)
        #expect(info.window(.model("x")) == nil)
    }

    @Test func primaryFallsBackToWeeklyThenFirst() {
        let weekly = UsageWindow(kind: .weekly, usedPercent: 50, windowMinutes: 10080, resetsAt: nil)
        let sonnet = UsageWindow(kind: .model("Sonnet"), usedPercent: 5, windowMinutes: 10080, resetsAt: nil)
        func info(_ w: [UsageWindow]) -> UsageInfo {
            UsageInfo(providerID: "c", providerName: "c", windows: w, plan: nil, lastUpdated: .distantPast)
        }
        #expect(info([sonnet, weekly]).primary == weekly)
        #expect(info([sonnet]).primary == sonnet)
        #expect(info([]).primary == nil)
    }

    @Test func invalidInputNeverEscapesRange() {
        let negative = UsageWindow(kind: .session, usedPercent: -20, windowMinutes: nil, resetsAt: nil)
        #expect(negative.remainingPercent == 100)
        let nan = UsageWindow(kind: .session, usedPercent: .nan, windowMinutes: nil, resetsAt: nil)
        #expect(nan.displayUsedPercent == 0)
        #expect(nan.remainingPercent == 100)
    }

    @Test func pastResetMarksOutdatedNotZero() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let w = UsageWindow(kind: .session, usedPercent: 90, windowMinutes: 300, resetsAt: now.addingTimeInterval(-1))
        #expect(w.isOutdated(now: now))
        #expect(w.usedPercent == 90)
        #expect(!UsageWindow(kind: .session, usedPercent: 1, windowMinutes: nil, resetsAt: nil).isOutdated(now: now))
    }

    @Test func codableRoundTrip() throws {
        let info = UsageInfo(
            providerID: "codex", providerName: "OpenAI Codex",
            windows: [UsageWindow(kind: .model("Sonnet"), usedPercent: 33, windowMinutes: 10080,
                                  resetsAt: Date(timeIntervalSince1970: 1_800_000_000))],
            plan: "plus", lastUpdated: Date(timeIntervalSince1970: 1_799_999_000))
        let data = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(UsageInfo.self, from: data) == info)
    }
}
