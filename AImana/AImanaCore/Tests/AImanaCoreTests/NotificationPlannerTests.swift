import Foundation
import Testing
@testable import AImanaCore

@Suite struct NotificationPlannerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let en = Locale(identifier: "en")
    private let on = NotificationPreferences(isEnabled: true)

    /// A Claude reading `minutes` after `start`; the session window resets at `reset` (hours after `start`).
    private func reading(_ used: Double, at minutes: Double = 0, reset: Double? = 4.5, lane: AlertLane = .session,
                         id: String = "claude", error: UsageProviderError? = nil) -> ProviderState {
        let when = start.addingTimeInterval(minutes * 60)
        let window = UsageWindow(kind: lane.kind, usedPercent: used, windowMinutes: lane == .session ? 300 : 10080,
                                 resetsAt: reset.map { start.addingTimeInterval($0 * 3600) })
        let usage = UsageInfo(providerID: id, providerName: id == "claude" ? "Claude Code" : "OpenAI Codex",
                              windows: [window], plan: nil, lastUpdated: when)
        return ProviderState(providerID: id, displayName: usage.providerName, usage: usage, error: error)
    }

    /// Feeds readings in order and returns every immediate notification per step.
    private func run(_ steps: [ProviderState], prefs: NotificationPreferences? = nil, mode: DisplayMode = .used,
                     state initial: NotificationState = NotificationState()) -> (sent: [[PlannedNotification]], last: NotificationPlan) {
        var state = initial
        var sent: [[PlannedNotification]] = []
        var last: NotificationPlan!
        for step in steps {
            let now = step.usage?.lastUpdated ?? start
            last = NotificationPlanner.plan(state: state, states: [step], logins: [:], preferences: prefs ?? on,
                                            displayMode: mode, now: now, locale: en)
            state = last.state
            sent.append(last.deliver)
        }
        return (sent, last)
    }

    private func kinds(_ sent: [[PlannedNotification]]) -> [[PlannedNotification.Kind]] {
        sent.map { $0.map(\.kind) }
    }

    @Test func crossingUpAlertsOncePerThreshold() {
        let result = run([reading(70), reading(82, at: 10), reading(85, at: 20), reading(96, at: 30), reading(97, at: 40)])
        // Pace is fast from the second reading on; it is checked separately.
        let thresholds = result.sent.map { $0.filter { if case .threshold = $0.kind { true } else { false } }.map(\.kind) }
        #expect(thresholds == [[], [.threshold(80)], [], [.threshold(95)], []])
        let alert = result.sent[1].first { $0.kind == .threshold(80) }
        #expect(alert?.title == "Claude Code · Session (5h)")
        #expect(alert?.body.hasPrefix("Now at 82% used, past your 80% alert.") == true)
        #expect(alert?.threadID == "provider.claude")
    }

    @Test func firstSightingIsASilentBaseline() {
        let result = run([reading(90)])
        #expect(kinds(result.sent) == [[.fastPace]])   // no threshold, only the (non-crossing) pace alert
        #expect(result.last.state.windows["claude.session"]?.firedThresholds == [])
    }

    @Test func jumpPastSeveralThresholdsSendsOnlyTheHighest() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(10), reading(97, at: 5)], prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(95)]])
        #expect(result.last.state.windows["claude.session"]?.firedThresholds == [80, 95])
    }

    @Test func jitterAroundAThresholdDoesNotRepeat() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(79, at: 0), reading(81, at: 5), reading(79.5, at: 10), reading(81, at: 15)], prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(80)], [], []])
    }

    @Test func windowResetClearsDedupe() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(70), reading(85, at: 10),
                          // Next 5-hour window: resets 5 h later than the first.
                          reading(5, at: 280, reset: 9.5), reading(82, at: 300, reset: 9.5)], prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(80)], [], [.threshold(80)]])
    }

    @Test func smallResetJitterIsTheSameWindow() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(70), reading(85, at: 10, reset: 4.5 + 1 / 3600),
                          reading(86, at: 20, reset: 4.5 - 2 / 3600)], prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(80)], []])
    }

    @Test func thresholdsIgnoreTheDisplayMode() {
        let steps = [reading(70), reading(82, at: 10), reading(96, at: 20)]
        let used = run(steps, mode: .used)
        let remaining = run(steps, mode: .remaining)
        #expect(kinds(used.sent) == kinds(remaining.sent))
        #expect(used.last.state == remaining.last.state)
    }

    @Test func disabledLaneConsumesCrossingsSilently() {
        var prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        prefs.setWindow(WindowAlertSettings(isEnabled: false), providerID: "claude", lane: .session)
        let result = run([reading(70), reading(85, at: 10)], prefs: prefs)
        #expect(kinds(result.sent) == [[], []])
        prefs.setWindow(WindowAlertSettings(isEnabled: true), providerID: "claude", lane: .session)
        let resumed = run([reading(86, at: 20)], prefs: prefs, state: result.last.state)
        #expect(kinds(resumed.sent) == [[]])
    }

    @Test func masterSwitchOffSendsNothingButKeepsTracking() {
        let off = NotificationPreferences(isEnabled: false)
        let result = run([reading(70), reading(97, at: 10)], prefs: off)
        #expect(kinds(result.sent) == [[], []])
        #expect(result.last.pending.isEmpty)
        #expect(result.last.state.windows["claude.session"]?.firedThresholds == [80, 95])
    }

    @Test func staleAndOutdatedReadingsNeverAlert() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let base = run([reading(70)], prefs: prefs).last.state
        // Failed refresh keeping last known data.
        let failed = run([reading(99, at: 10, error: .network)], prefs: prefs, state: base)
        #expect(kinds(failed.sent) == [[]])
        #expect(failed.last.state == base)
        // Reading whose reset already passed.
        let outdated = run([reading(99, at: 300, reset: 4.5)], prefs: prefs, state: base)
        #expect(kinds(outdated.sent) == [[]])
        // Replay of an older reading (e.g. the cached snapshot after a direct refresh).
        let newer = run([reading(75, at: 20)], prefs: prefs, state: base).last.state
        let replay = run([reading(99, at: 10)], prefs: prefs, state: newer)
        #expect(kinds(replay.sent) == [[]])
    }

    @Test func recoveryIsScheduledForTheResetOfAnArmedWindow() throws {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(70), reading(96, at: 10)], prefs: prefs)
        let pending = try #require(result.last.pending.first)
        #expect(pending.id == "recovered.claude.session")
        #expect(pending.kind == .recovered)
        #expect(pending.trigger == .at(start.addingTimeInterval(4.5 * 3600)))

        let quiet = run([reading(70), reading(85, at: 10)], prefs: prefs)
        #expect(quiet.last.pending.isEmpty)   // 85 % is below the highest threshold (95 %)

        let noRecovery = NotificationPreferences(isEnabled: true, paceAlerts: false, recoveryAlerts: false)
        #expect(run([reading(70), reading(96, at: 10)], prefs: noRecovery).last.pending.isEmpty)
    }

    @Test func recoveryAfterTheScheduledTimeIsNotRepeated() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(70), reading(100, at: 10), reading(3, at: 280, reset: 9.5)], prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(95)], []])
        #expect(result.last.pending.isEmpty)
    }

    @Test func recoveryWithoutAKnownResetIsSentWhenNoticed() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        let result = run([reading(90, reset: nil), reading(100, at: 10, reset: nil), reading(4, at: 400, reset: nil)],
                         prefs: prefs)
        #expect(kinds(result.sent) == [[], [.threshold(95)], [.recovered]])
        #expect(result.sent[2].first?.trigger == .now)
        #expect(result.sent[2].first?.body == "It has reset. Quota is available again.")
    }

    @Test func fastPaceAlertsOncePerWindow() {
        // 2 of 5 hours elapsed (reset in 3 h): 60 % used projects to 150 % at reset.
        let result = run([reading(50, reset: 3), reading(60, at: 5, reset: 3), reading(65, at: 10, reset: 3),
                          reading(60, at: 200, reset: 8)],
                         prefs: NotificationPreferences(isEnabled: true, windowAlerts: [
                             "claude.session": WindowAlertSettings(thresholds: [100])]))
        #expect(kinds(result.sent) == [[.fastPace], [], [], [.fastPace]])
        #expect(result.sent[0].first?.body.hasPrefix("At this pace it runs out in") == true)
    }

    @Test func comfortablePaceStaysQuiet() {
        let result = run([reading(10, reset: 3), reading(20, at: 10, reset: 3)])
        #expect(kinds(result.sent) == [[], []])
    }

    @Test func expiredLoginAlertsOnceUntilSignedInAgain() {
        var state = NotificationState()
        func step(_ status: PhoneLoginStatus, prefs: NotificationPreferences? = nil) -> [PlannedNotification.Kind] {
            let plan = NotificationPlanner.plan(state: state, states: [], logins: ["codex": status],
                                                preferences: prefs ?? on, now: start, locale: en)
            state = plan.state
            return plan.deliver.map(\.kind)
        }
        #expect(step(.expired) == [.loginExpired])
        #expect(step(.expired) == [])
        #expect(step(.active) == [])
        #expect(step(.expired) == [.loginExpired])
        #expect(step(.signedOut) == [])
        #expect(step(.expired, prefs: NotificationPreferences(isEnabled: false)) == [])
        #expect(step(.expired) == [.loginExpired])

        let plan = NotificationPlanner.plan(state: NotificationState(), states: [], logins: ["codex": .expired],
                                            preferences: on, now: start, locale: en)
        #expect(plan.deliver.first?.title == "ChatGPT sign-in expired")
        #expect(plan.deliver.first?.threadID == "provider.codex")
    }

    @Test func unknownLoginStatusLeavesDedupeAlone() {
        let state = NotificationState(loginNotified: ["claude"])
        let plan = NotificationPlanner.plan(state: state, states: [], logins: [:], preferences: on, now: start)
        #expect(plan.state.loginNotified == ["claude"])
    }

    @Test func dailySummaryFollowsTheDisplayModeAndSaysWhatReset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let prefs = NotificationPreferences(isEnabled: true, dailySummary: true, summaryMinutes: 21 * 60 + 30)
        let usage = UsageInfo(providerID: "codex", providerName: "OpenAI Codex", windows: [
            UsageWindow(kind: .session, usedPercent: 42, windowMinutes: 300, resetsAt: start.addingTimeInterval(600)),
            UsageWindow(kind: .weekly, usedPercent: 61, windowMinutes: 10080,
                        resetsAt: start.addingTimeInterval(3 * 86400)),
        ], plan: nil, lastUpdated: start)

        let used = try #require(NotificationPlanner.pending(state: NotificationState(), usages: [usage], preferences: prefs,
                                                            now: start, locale: en, calendar: calendar).first)
        #expect(used.trigger == .daily(hour: 21, minute: 30))
        #expect(used.title == "Daily usage summary")
        #expect(used.body.hasPrefix("OpenAI Codex: Session (5h) renewed · Weekly 61% used\nData from "))

        let left = try #require(NotificationPlanner.pending(state: NotificationState(), usages: [usage], preferences: prefs,
                                                            displayMode: .remaining, now: start, locale: en,
                                                            calendar: calendar).first)
        #expect(left.body.hasPrefix("OpenAI Codex: Session (5h) renewed · Weekly 39% left"))

        let off = NotificationPreferences(isEnabled: true)
        #expect(NotificationPlanner.pending(state: NotificationState(), usages: [usage], preferences: off,
                                            now: start, calendar: calendar).isEmpty)
    }

    @Test func otherProvidersAndLanesAreTrackedSeparately() {
        let prefs = NotificationPreferences(isEnabled: true, paceAlerts: false)
        var state = NotificationState()
        for (minute, claude, codex) in [(0.0, 70.0, 70.0), (10, 82, 70)] {
            let plan = NotificationPlanner.plan(state: state, states: [reading(claude, at: minute),
                                                                       reading(codex, at: minute, lane: .weekly, id: "codex")],
                                                logins: [:], preferences: prefs, now: start.addingTimeInterval(minute * 60),
                                                locale: en)
            state = plan.state
            if minute > 0 { #expect(plan.deliver.map(\.id).allSatisfy { $0.hasPrefix("threshold.claude.session.") }) }
        }
        #expect(Set(state.windows.keys) == ["claude.session", "codex.weekly"])
    }
}

@Suite struct NotificationPreferencesTests {
    @Test func thresholdsAreNormalized() {
        #expect(NotificationPreferences.normalized([3, 81, 80, 200, 50]) == [5, 50, 80, 100])
        #expect(NotificationPreferences.normalized([10, 20, 30, 40, 50, 60]) == [10, 20, 30, 40, 50])
        #expect(WindowAlertSettings().thresholds == [80, 95])
    }

    @Test func defaultsAreOffAndMissingFieldsKeepTheirDefaults() throws {
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(decoded.isEnabled)
        #expect(decoded.paceAlerts && decoded.recoveryAlerts && decoded.loginAlerts)
        #expect(!decoded.dailySummary)
        #expect(decoded.summaryMinutes == 20 * 60)
        #expect(!NotificationPreferences().isEnabled)
        #expect(NotificationPreferences().window(providerID: "codex", lane: .weekly) == WindowAlertSettings())
    }

    @Test func storeRoundTripsThroughUserDefaults() throws {
        let suite = "NotificationPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NotificationStore.preferences(defaults: defaults) == NotificationPreferences())

        var prefs = NotificationPreferences(isEnabled: true, dailySummary: true, summaryMinutes: 7 * 60)
        prefs.setWindow(WindowAlertSettings(isEnabled: false, thresholds: [50]), providerID: "claude", lane: .weekly)
        NotificationStore.setPreferences(prefs, defaults: defaults)
        #expect(NotificationStore.preferences(defaults: defaults) == prefs)

        let state = NotificationState(windows: [:], loginNotified: ["codex"])
        NotificationStore.setState(state, defaults: defaults)
        #expect(NotificationStore.state(defaults: defaults) == state)
    }

    @Test func crossedThresholdsOnlyCountsUpwardCrossings() {
        #expect(SeverityTransitions.crossedThresholds([80, 95], from: 70, to: 96) == [80, 95])
        #expect(SeverityTransitions.crossedThresholds([80, 95], from: 85, to: 90) == [])
        #expect(SeverityTransitions.crossedThresholds([80, 95], from: 96, to: 70) == [])
        #expect(SeverityTransitions.crossedThresholds([80, 95], from: 70, to: 96, alreadyFired: [80]) == [95])
        #expect(SeverityTransitions.crossedThresholds([100], from: 99, to: 100) == [100])
    }
}
