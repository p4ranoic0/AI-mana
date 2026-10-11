import Foundation

public struct BurndownSample: Sendable, Equatable, Identifiable {
    public let time: Date
    public let percent: Double

    public var id: Date { time }

    public init(time: Date, percent: Double) {
        self.time = time
        self.percent = percent
    }
}

/// Chart-ready readings for one current quota window. All filtering and projection stay outside SwiftUI.
public struct Burndown: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let actual: [BurndownSample]
    public let guide: [BurndownSample]
    public let projection: [BurndownSample]
    public let current: BurndownSample?
    public let recordedPointCount: Int

    public var hasEnoughHistory: Bool { recordedPointCount >= 2 }

    public init?(providerID: String, window: UsageWindow, history: [HistorySeries],
                 mode: DisplayMode, observedAt: Date) {
        guard let minutes = window.windowMinutes, minutes > 0,
              let end = window.resetsAt else { return nil }
        let startDate = end.addingTimeInterval(-TimeInterval(minutes) * 60)
        self.end = end
        self.start = startDate

        func displayed(_ used: Double) -> Double {
            let safeUsed = used.isFinite ? min(100, max(0, used)) : 0
            return mode == .used ? safeUsed : 100 - safeUsed
        }

        let matched = history
            .filter { $0.providerID == providerID && $0.kind == window.kind }
            .flatMap(\.points)
            .filter { point in
                guard let reset = point.resetsAt else { return false }
                return abs(reset.timeIntervalSince(end)) <= 120
                    && point.t >= startDate && point.t <= end && point.used.isFinite
            }
            .sorted { $0.t < $1.t }
        self.recordedPointCount = matched.count

        var readings = matched.map { BurndownSample(time: $0.t, percent: displayed($0.used)) }
        let snapshot = observedAt >= startDate && observedAt <= end
            ? BurndownSample(time: observedAt, percent: mode.percent(for: window)) : nil
        if let snapshot, let last = readings.last, snapshot.time > last.time.addingTimeInterval(1) {
            readings.append(snapshot)
        }
        self.actual = readings
        self.current = snapshot ?? readings.last
        self.guide = [BurndownSample(time: startDate, percent: displayed(0)),
                      BurndownSample(time: end, percent: displayed(100))]

        if let snapshot, let pace = UsagePace(window: window, now: observedAt),
           pace.status == .comfortable || pace.status == .fast,
           let projected = pace.projectedUsedAtReset {
            var future = [snapshot]
            if pace.status == .fast, let exhaustsAt = pace.exhaustsAt,
               exhaustsAt > observedAt && exhaustsAt < end {
                future.append(BurndownSample(time: exhaustsAt, percent: displayed(100)))
            }
            future.append(BurndownSample(time: end, percent: displayed(projected)))
            self.projection = future
        } else {
            self.projection = []
        }
    }
}
