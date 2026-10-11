import Foundation
import Testing
@testable import AImanaCore

@Suite struct HistoryRecorderTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(_ id: String = "claude", session: Double? = 10, weekly: Double? = 30,
                       sessionReset: TimeInterval = 3600, extraModel: Bool = false) -> UsageInfo {
        var windows: [UsageWindow] = []
        if let session { windows.append(UsageWindow(kind: .session, usedPercent: session, windowMinutes: 300, resetsAt: t0.addingTimeInterval(sessionReset))) }
        if let weekly { windows.append(UsageWindow(kind: .weekly, usedPercent: weekly, windowMinutes: 10080, resetsAt: t0.addingTimeInterval(86400))) }
        if extraModel { windows.append(UsageWindow(kind: .model("Fable"), usedPercent: 1, windowMinutes: 10080, resetsAt: nil)) }
        return UsageInfo(providerID: id, providerName: id, windows: windows, plan: nil, lastUpdated: t0)
    }

    private func points(_ series: [HistorySeries], _ id: String, _ kind: UsageWindow.Kind) -> [HistoryPoint] {
        series.first { $0.providerID == id && $0.kind == kind }?.points ?? []
    }

    @Test func recordsSessionAndWeeklyButNotModelLanes() {
        let s = HistoryRecorder.append([], with: [usage(extraModel: true)], now: t0)
        #expect(s.count == 2)
        #expect(points(s, "claude", .session).first?.used == 10)
        #expect(points(s, "claude", .weekly).first?.used == 30)
        #expect(s.allSatisfy { $0.kind != .model("Fable") })
        #expect(points(s, "claude", .session).first?.resetsAt == t0.addingTimeInterval(3600))
    }

    @Test func unchangedReadingsWithinTenMinutesAreSkipped() {
        var s = HistoryRecorder.append([], with: [usage()], now: t0)
        s = HistoryRecorder.append(s, with: [usage()], now: t0.addingTimeInterval(300))
        #expect(points(s, "claude", .session).count == 1)
        s = HistoryRecorder.append(s, with: [usage()], now: t0.addingTimeInterval(601))
        #expect(points(s, "claude", .session).count == 2)   // heartbeat keeps the line continuous
    }

    @Test func changedUsageOrNewWindowIsAlwaysRecorded() {
        var s = HistoryRecorder.append([], with: [usage(session: 10)], now: t0)
        s = HistoryRecorder.append(s, with: [usage(session: 12)], now: t0.addingTimeInterval(60))
        #expect(points(s, "claude", .session).map(\.used) == [10, 12])
        // Window rolled over (new resetsAt) with identical usage: still a new point.
        s = HistoryRecorder.append(s, with: [usage(session: 12, sessionReset: 5 * 3600)], now: t0.addingTimeInterval(120))
        #expect(points(s, "claude", .session).count == 3)
    }

    @Test func missingWindowsAddNothing() {
        let s = HistoryRecorder.append([], with: [usage(session: nil, weekly: 40)], now: t0)
        #expect(points(s, "claude", .session).isEmpty)
        #expect(points(s, "claude", .weekly).count == 1)
    }

    @Test func providersAreIndependent() {
        let s = HistoryRecorder.append([], with: [usage("claude"), usage("codex", session: 50)], now: t0)
        #expect(points(s, "claude", .session).first?.used == 10)
        #expect(points(s, "codex", .session).first?.used == 50)
    }

    @Test func pointsOlderThanRetentionAreTrimmed() {
        var s = HistoryRecorder.append([], with: [usage(session: 5)], now: t0)
        let later = t0.addingTimeInterval(9 * 86400)
        s = HistoryRecorder.append(s, with: [usage(session: 6)], now: later)
        #expect(points(s, "claude", .session).map(\.used) == [6])
    }

    @Test func downsamplingKeepsRecentIntactAndBucketsOlder() {
        let now = t0.addingTimeInterval(3 * 86400)
        var pts: [HistoryPoint] = []
        // Two days of 5-minute samples ending 25 h ago, plus 2 h of 5-minute samples ending now.
        var t = now.addingTimeInterval(-73 * 3600)
        while t < now.addingTimeInterval(-25 * 3600) { pts.append(HistoryPoint(t: t, used: 1, resetsAt: nil)); t += 300 }
        t = now.addingTimeInterval(-2 * 3600)
        while t <= now { pts.append(HistoryPoint(t: t, used: 2, resetsAt: nil)); t += 300 }
        let out = HistoryRecorder.downsampled([HistorySeries(providerID: "claude", kind: .session, points: pts)], now: now)
        let result = out[0].points
        let recent = result.filter { $0.t >= now.addingTimeInterval(-24 * 3600) }
        #expect(recent.count == 25)                       // untouched: 2 h at 5 min (+1)
        let old = result.filter { $0.t < now.addingTimeInterval(-24 * 3600) }
        #expect(old.count <= 48 * 2 + 1)                  // ≤ one per 30 min over 48 h
        #expect(old.count < 300)                          // far fewer than the raw ~576
        #expect(result == result.sorted { $0.t < $1.t })
    }
}
