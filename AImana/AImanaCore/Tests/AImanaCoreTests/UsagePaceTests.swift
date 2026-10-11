import Foundation
import Testing
@testable import AImanaCore

@Suite struct UsagePaceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// 5 h session with `elapsedMinutes` already gone.
    private func session(used: Double, elapsedMinutes: Double) -> UsageWindow {
        UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300,
                    resetsAt: now.addingTimeInterval((300 - elapsedMinutes) * 60))
    }

    @Test func comfortableWhenBelowExpected() throws {
        // 150 of 300 min elapsed → expected 50 %; used 35 % → projected 70 %.
        let pace = try #require(UsagePace(window: session(used: 35, elapsedMinutes: 150), now: now))
        #expect(pace.status == .comfortable)
        #expect(abs(pace.expectedUsedPercent - 50) < 0.001)
        #expect(abs((pace.projectedUsedAtReset ?? 0) - 70) < 0.001)
        #expect(pace.exhaustsAt == nil)
    }

    @Test func fastProjectsExhaustionBeforeReset() throws {
        // Expected 50 %, used 80 % at 150 min → rate 0.5333 %/min → hits 100 % after 37.5 more min.
        let pace = try #require(UsagePace(window: session(used: 80, elapsedMinutes: 150), now: now))
        #expect(pace.status == .fast)
        let exhausts = try #require(pace.exhaustsAt)
        #expect(abs(exhausts.timeIntervalSince(now) - 37.5 * 60) < 1)
        #expect(exhausts < session(used: 80, elapsedMinutes: 150).resetsAt!)
    }

    @Test func smallOvershootIsNotFlaggedFast() throws {
        // Expected 50 %, used 52 % → projected 104 %, inside the 5 % tolerance.
        let pace = try #require(UsagePace(window: session(used: 52, elapsedMinutes: 150), now: now))
        #expect(pace.status == .comfortable)
    }

    @Test func depletedAtOrAboveHundred() throws {
        #expect(UsagePace(window: session(used: 100, elapsedMinutes: 100), now: now)?.status == .depleted)
        #expect(UsagePace(window: session(used: 130, elapsedMinutes: 100), now: now)?.status == .depleted)
    }

    @Test func tooEarlyWhenWindowJustStarted() throws {
        // 10 of 300 min = 3 % elapsed: a projection would be noise.
        let pace = try #require(UsagePace(window: session(used: 9, elapsedMinutes: 10), now: now))
        #expect(pace.status == .tooEarly)
        #expect(pace.projectedUsedAtReset == nil)
        #expect(pace.exhaustsAt == nil)
    }

    @Test func zeroUsageIsComfortable() throws {
        let pace = try #require(UsagePace(window: session(used: 0, elapsedMinutes: 200), now: now))
        #expect(pace.status == .comfortable)
        #expect(pace.projectedUsedAtReset == 0)
    }

    @Test func unavailableWithoutUsableWindowData() {
        let noReset = UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: nil)
        let noDuration = UsageWindow(kind: .session, usedPercent: 10, windowMinutes: nil, resetsAt: now.addingTimeInterval(3600))
        let outdated = UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: now.addingTimeInterval(-60))
        let nonFinite = UsageWindow(kind: .session, usedPercent: .nan, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600))
        #expect(UsagePace(window: noReset, now: now) == nil)
        #expect(UsagePace(window: noDuration, now: now) == nil)
        #expect(UsagePace(window: outdated, now: now) == nil)
        // NaN is sanitised to 0 used, so it is still a (comfortable) reading rather than a crash.
        #expect(UsagePace(window: nonFinite, now: now)?.status == .comfortable)
    }

    @Test func weeklyWindowUsesItsOwnDuration() throws {
        // 7-day window, 3.5 days left → expected 50 %; used 20 % → comfortable.
        let w = UsageWindow(kind: .weekly, usedPercent: 20, windowMinutes: 10080,
                            resetsAt: now.addingTimeInterval(3.5 * 86400))
        let pace = try #require(UsagePace(window: w, now: now))
        #expect(abs(pace.expectedUsedPercent - 50) < 0.001)
        #expect(pace.status == .comfortable)
    }

    @Test func compactPaceTextDropsBeforeReset() throws {
        let fast = try #require(UsagePace(window: session(used: 80, elapsedMinutes: 150), now: now))
        #expect(UsageFormatter.paceText(fast, now: now, compact: true, locale: Locale(identifier: "en_US")) == "Fast · runs out in 38m")
        let ok = try #require(UsagePace(window: session(used: 35, elapsedMinutes: 150), now: now))
        #expect(UsageFormatter.paceText(ok, now: now, compact: true, locale: Locale(identifier: "en_US")) == "On pace · ends ~70% used")
    }

    @Test func noPaceTextWhenNothingSpent() throws {
        let idle = try #require(UsagePace(window: session(used: 0, elapsedMinutes: 200), now: now))
        #expect(UsageFormatter.paceText(idle, now: now) == nil)
    }

    @Test func paceTextWording() throws {
        let comfortable = try #require(UsagePace(window: session(used: 35, elapsedMinutes: 150), now: now))
        #expect(UsageFormatter.paceText(comfortable, now: now, locale: Locale(identifier: "en_US")) == "On pace · ends ~70% used")

        let fast = try #require(UsagePace(window: session(used: 80, elapsedMinutes: 150), now: now))
        #expect(UsageFormatter.paceText(fast, now: now, locale: Locale(identifier: "en_US")) == "Fast · runs out in 38m, before reset")

        let depleted = try #require(UsagePace(window: session(used: 100, elapsedMinutes: 100), now: now))
        #expect(UsageFormatter.paceText(depleted, now: now, locale: Locale(identifier: "en_US")) == "Depleted")

        let early = try #require(UsagePace(window: session(used: 9, elapsedMinutes: 10), now: now))
        #expect(UsageFormatter.paceText(early, now: now) == nil)
    }
}
