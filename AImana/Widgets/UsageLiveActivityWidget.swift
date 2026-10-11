import AImanaCore
import ActivityKit
import SwiftUI
import WidgetKit

struct UsageLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UsageActivityAttributes.self) { context in
            LiveActivityLockScreen(attributes: context.attributes, state: context.state,
                                   isStale: context.isStale)
                .padding(SoftTheme.cardPadding)
                .background(WidgetCanvas(accent: SoftTheme.providerTint(context.attributes.providerID)))
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.providerName,
                          systemImage: SoftTheme.providerSymbol(context.attributes.providerID))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveReset(state: context.state, compact: true, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityLanes(state: context.state)
                        .padding(.top, SoftTheme.Space.sm)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: SoftTheme.providerSymbol(context.attributes.providerID))
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    Text(UsageFormatter.percentText(context.state.displayMode.percent(for: context.state.sessionWindow)))
                        .monospacedDigit()
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .accessibilityLabel("\(context.attributes.providerName), \(UsageFormatter.percentText(context.state.displayMode.percent(for: context.state.sessionWindow))) \(context.state.displayMode.caption)")
            } compactTrailing: {
                LiveReset(state: context.state, compact: true, isStale: context.isStale)
            } minimal: {
                LiveMinimalRing(state: context.state)
            }
            .keylineTint(UsageSeverity(remainingPercent: 100 - context.state.sessionUsedPercent).tint)
        }
    }
}

private struct LiveActivityLockScreen: View {
    let attributes: UsageActivityAttributes
    let state: UsageActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack {
                Image(systemName: SoftTheme.providerSymbol(attributes.providerID))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(attributes.providerName)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer(minLength: 0)
                Text(UsageFormatter.percentText(state.displayMode.percent(for: state.sessionWindow)))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            LiveActivityLanes(state: state)
            LiveReset(state: state, compact: false, isStale: isStale)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

private struct LiveActivityLanes: View {
    let state: UsageActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            lane(state.sessionWindow, title: WidgetStrings.text("Session"), marker: true)
            if let weekly = state.weeklyWindow {
                lane(weekly, title: WidgetStrings.text("Weekly"), marker: false)
            }
            if state.paceStatus == .fast, let exhaustsAt = state.exhaustsAt {
                HStack(spacing: 4) {
                    Text(WidgetStrings.text("Fast · runs out in"))
                    if exhaustsAt > Date() {
                        Text(timerInterval: Date()...exhaustsAt, countsDown: true)
                            .monospacedDigit()
                    } else {
                        Text(WidgetStrings.text("Depleted"))
                    }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(UsageSeverity(remainingPercent: 100 - state.sessionUsedPercent).tint)
            } else if state.paceStatus == .depleted {
                Text(WidgetStrings.text("Depleted"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
            } else if state.paceStatus == .comfortable {
                Text(WidgetStrings.text("On pace"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lane(_ window: UsageWindow, title: String, marker: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                Text(UsageFormatter.percentText(state.displayMode.percent(for: window)))
                    .monospacedDigit()
                Text(state.displayMode.caption)
            }
            .font(.system(.caption, design: .rounded, weight: .medium))
            UsageBar(window: window, mode: state.displayMode,
                     pace: marker ? UsagePace(window: window, now: state.lastUpdated) : nil)
                .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LiveReset: View {
    let state: UsageActivityAttributes.ContentState
    let compact: Bool
    let isStale: Bool

    var body: some View {
        Group {
            if isStale || Date().timeIntervalSince(state.lastUpdated) > 3600 || state.sessionResetsAt <= Date() {
                HStack(spacing: 3) {
                    Text(WidgetStrings.text("Updated"))
                    Text(state.lastUpdated, style: .relative)
                }
                .foregroundStyle(.secondary)
            } else if state.paceStatus == .fast, let exhaustsAt = state.exhaustsAt,
                      exhaustsAt > Date(), compact {
                Text(timerInterval: Date()...exhaustsAt, countsDown: true)
                    .foregroundStyle(.orange)
                    .accessibilityHint(WidgetStrings.text("Runs out in"))
            } else if state.sessionResetsAt > Date() {
                HStack(spacing: 3) {
                    if !compact { Text(WidgetStrings.text("Resets in")) }
                    Text(timerInterval: Date()...state.sessionResetsAt, countsDown: true)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            } else {
                Text(WidgetStrings.text("Outdated"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption, design: .rounded, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

private struct LiveMinimalRing: View {
    let state: UsageActivityAttributes.ContentState

    var body: some View {
        let window = state.sessionWindow
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: state.displayMode.percent(for: window) / 100)
                .stroke(UsageSeverity(remainingPercent: window.remainingPercent).tint,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("\(UsageFormatter.percentText(state.displayMode.percent(for: window))) \(state.displayMode.caption), \(UsageSeverity(remainingPercent: window.remainingPercent).statusText)")
    }
}
