import AImanaCore
import SwiftUI

struct OverviewHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 130
    let summary: OverviewSummary

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                    HStack { Spacer(); rings; Spacer() }
                    details
                }
            } else {
                if sizeClass == .regular {
                    // Wide windows: the lane pills keep a readable length and the pair sits centred in the card.
                    HStack(alignment: .center, spacing: SoftTheme.Space.xxl) {
                        rings
                        details.frame(maxWidth: AdaptiveLayout.heroDetailsMaxWidth)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .center, spacing: SoftTheme.Space.lg) {
                        rings
                        details
                    }
                }
            }
        }
        .padding(SoftTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softSurface(tint: SoftTheme.peach)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rings: some View {
        ZStack {
            ForEach(Array(summary.lanes.enumerated()), id: \.element.id) { index, lane in
                OverviewRingLane(lane: lane, diameter: max(48, ringSize - CGFloat(index) * 25))
            }
            VStack(spacing: 0) {
                Text(UsageFormatter.percentText(summary.highlighted.displayPercent))
                    .softText(.headline).fontWeight(.bold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth, value: summary.highlighted.displayPercent)
                Text(summary.mode.caption)
                    .softText(.caption)
                    .foregroundStyle(.secondary)
            }
            // Keep the figure inside the hole left by the four lanes instead of touching the inner ring.
            .frame(width: max(44, ringSize - 4 * 25 - 14))
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            Text(AppStrings.text(summary.mode == .used ? "Highest right now" : "Lowest remaining"))
                .softText(.body)
                .foregroundStyle(.secondary)
            Text("\(shortName(summary.highlighted.providerID, fallback: summary.highlighted.providerName)) \(kindName(summary.highlighted.window.kind))")
                .softText(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let reset = UsageFormatter.resetText(for: summary.highlighted.window.resetsAt, now: .now) {
                Text(reset).softText(.caption).foregroundStyle(.secondary)
            }
            if let budget = DailyBudget(window: summary.highlighted.window), budget.status == .spread {
                Text(AppStrings.format("Daily budget %@", budget.compactText()))
                    .softText(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SoftTheme.Space.xs)],
                      alignment: .leading, spacing: SoftTheme.Space.xs) {
                ForEach(summary.lanes) { lane in
                    // Window length instead of "wk": "5 h" and "7 d" read the same in every language.
                    HStack(spacing: SoftTheme.Space.xs) {
                        Text(verbatim: shortName(lane.providerID, fallback: lane.providerName)).fontWeight(.semibold)
                        Text(verbatim: windowLength(lane.window)).foregroundStyle(SoftTheme.ink.opacity(0.6))
                        Spacer(minLength: 2)
                        Text(UsageFormatter.percentText(lane.displayPercent)).fontWeight(.bold).monospacedDigit()
                    }
                        .softText(.caption)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(SoftTheme.ink)
                        .padding(.horizontal, SoftTheme.Space.sm).padding(.vertical, SoftTheme.Space.xs)
                        .frame(maxWidth: .infinity)
                        .background(SoftTheme.laneTint(providerID: lane.providerID, kind: lane.window.kind),
                                    in: Capsule())
                }
            }
            .padding(.top, SoftTheme.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        let featured = summary.highlighted
        let laneDescriptions = summary.lanes.map {
            "\($0.providerName) \(kindName($0.window.kind)), \(UsageFormatter.percentText($0.displayPercent)) \(summary.mode.caption)"
        }
        return "\(AppStrings.text(summary.mode == .used ? "Highest usage" : "Lowest remaining")): \(featured.providerName) \(kindName(featured.window.kind)), \(UsageFormatter.percentText(featured.displayPercent)). "
            + laneDescriptions.joined(separator: ". ")
    }

    private func shortName(_ id: String, fallback: String) -> String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        default: fallback
        }
    }

    private func windowLength(_ window: UsageWindow) -> String {
        guard let minutes = window.windowMinutes, minutes > 0 else { return "" }
        return minutes % 1440 == 0 ? "\(minutes / 1440) d" : "\(max(1, minutes / 60)) h"
    }

    private func kindName(_ kind: UsageWindow.Kind) -> String {
        AppStrings.text(kind == .weekly ? "weekly" : "session")
    }
}

private struct OverviewRingLane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var fill = 0.0
    let lane: OverviewLane
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(scheme == .dark ? .white.opacity(0.13) : .black.opacity(0.06), lineWidth: 7)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(SoftTheme.laneTint(providerID: lane.providerID, kind: lane.window.kind),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .onAppear { update() }
        .onChange(of: lane.displayPercent) { _, _ in update() }
        .onChange(of: reduceMotion) { _, _ in update() }
    }

    private func update() {
        let target = lane.displayPercent / 100
        if reduceMotion { fill = target }
        else { withAnimation(.smooth(duration: 0.7)) { fill = target } }
    }
}
