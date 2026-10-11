import Foundation

public struct OverviewLane: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let providerName: String
    public let window: UsageWindow
    public let displayPercent: Double

    public var id: String { "\(providerID):\(window.kind.wireValue)" }
}

/// The current session and weekly lanes of up to two providers, in a stable display order.
public struct OverviewSummary: Sendable, Equatable {
    public let lanes: [OverviewLane]
    public let highlighted: OverviewLane
    public let mode: DisplayMode

    public init?(usages: [UsageInfo], mode: DisplayMode) {
        var result: [OverviewLane] = []
        for usage in usages.prefix(2) {
            for kind in [UsageWindow.Kind.session, .weekly] {
                guard let window = usage.window(kind) else { continue }
                result.append(OverviewLane(providerID: usage.providerID,
                                           providerName: usage.providerName,
                                           window: window,
                                           displayPercent: mode.percent(for: window)))
            }
        }
        guard var winner = result.first else { return nil }
        for lane in result.dropFirst() {
            let moreUrgent = mode == .used
                ? lane.displayPercent > winner.displayPercent
                : lane.displayPercent < winner.displayPercent
            if moreUrgent { winner = lane }
        }
        lanes = result
        highlighted = winner
        self.mode = mode
    }
}
