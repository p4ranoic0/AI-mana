import Foundation

/// Keeps a bounded history of used-% readings so the iPhone can draw burndown charts even though it only
/// sees the latest snapshot. Pure functions; the relay and `UsageHistoryStore` own persistence.
public enum HistoryRecorder {
    public static let retention: TimeInterval = 8 * 86400
    /// An unchanged reading is re-recorded after this long so a flat line stays continuous.
    static let heartbeat: TimeInterval = 10 * 60
    /// Readings older than this are thinned out when published.
    static let fullResolutionWindow: TimeInterval = 24 * 3600
    static let oldBucket: TimeInterval = 30 * 60

    public static func append(_ series: [HistorySeries], with usages: [UsageInfo], now: Date) -> [HistorySeries] {
        var result = series
        for usage in usages {
            for window in usage.windows where window.kind == .session || window.kind == .weekly {
                guard window.usedPercent.isFinite else { continue }
                let point = HistoryPoint(t: now, used: window.usedPercent, resetsAt: window.resetsAt)
                if let index = result.firstIndex(where: { $0.providerID == usage.providerID && $0.kind == window.kind }) {
                    var points = result[index].points
                    if let last = points.last, last.used == point.used, last.resetsAt == point.resetsAt,
                       now.timeIntervalSince(last.t) < heartbeat { continue }
                    points.append(point)
                    result[index] = HistorySeries(providerID: usage.providerID, kind: window.kind, points: points)
                } else {
                    result.append(HistorySeries(providerID: usage.providerID, kind: window.kind, points: [point]))
                }
            }
        }
        let cutoff = now.addingTimeInterval(-retention)
        return result.map {
            HistorySeries(providerID: $0.providerID, kind: $0.kind, points: $0.points.filter { $0.t >= cutoff })
        }.filter { !$0.points.isEmpty }
    }

    /// Records only readings newer than what the series already holds, timestamped when the provider produced
    /// them, so a relay snapshot re-read hours later is not stored as a fresh reading.
    public static func record(_ series: [HistorySeries], with usages: [UsageInfo], now: Date) -> [HistorySeries] {
        var result = series
        for usage in usages where usage.lastUpdated <= now.addingTimeInterval(60) {
            let latest = result.filter { $0.providerID == usage.providerID }.compactMap { $0.points.last?.t }.max()
            if let latest, usage.lastUpdated <= latest { continue }
            result = append(result, with: [usage], now: usage.lastUpdated)
        }
        let cutoff = now.addingTimeInterval(-retention)
        return result.map {
            HistorySeries(providerID: $0.providerID, kind: $0.kind, points: $0.points.filter { $0.t >= cutoff })
        }.filter { !$0.points.isEmpty }
    }

    /// Readings closer than this to one already kept are treated as the same moment when merging sources.
    static let mergeTolerance: TimeInterval = 120

    /// Combines two recordings of the same lanes (the phone's own and the Mac relay's). Per lane the denser
    /// series is kept whole and the other only fills gaps, so overlapping stretches are not doubled.
    public static func merged(_ a: [HistorySeries], _ b: [HistorySeries]) -> [HistorySeries] {
        var order: [(String, UsageWindow.Kind)] = []
        for s in a + b where !order.contains(where: { $0.0 == s.providerID && $0.1 == s.kind }) {
            order.append((s.providerID, s.kind))
        }
        return order.map { id, kind in
            let left = a.filter { $0.providerID == id && $0.kind == kind }.flatMap(\.points)
            let right = b.filter { $0.providerID == id && $0.kind == kind }.flatMap(\.points)
            let (dense, sparse) = left.count >= right.count ? (left, right) : (right, left)
            var points = dense
            let times = dense.map(\.t)
            for point in sparse where !times.contains(where: { abs($0.timeIntervalSince(point.t)) < mergeTolerance }) {
                points.append(point)
            }
            return HistorySeries(providerID: id, kind: kind, points: points.sorted { $0.t < $1.t })
        }
    }

    /// Full resolution for the last 24 h, one point per 30 minutes (the latest in each bucket) before that.
    public static func downsampled(_ series: [HistorySeries], now: Date) -> [HistorySeries] {
        let boundary = now.addingTimeInterval(-fullResolutionWindow)
        return series.map { s in
            var buckets: [Int: HistoryPoint] = [:]
            var recent: [HistoryPoint] = []
            for point in s.points {
                if point.t >= boundary {
                    recent.append(point)
                } else {
                    let bucket = Int(floor(point.t.timeIntervalSince1970 / oldBucket))
                    if let existing = buckets[bucket], existing.t >= point.t { continue }
                    buckets[bucket] = point
                }
            }
            let merged = (Array(buckets.values) + recent).sorted { $0.t < $1.t }
            return HistorySeries(providerID: s.providerID, kind: s.kind, points: merged)
        }
    }
}
