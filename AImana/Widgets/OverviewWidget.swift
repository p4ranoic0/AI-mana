import AImanaCore
import SwiftUI
import WidgetKit

/// Large widget: every lane with its pace marker, plus what the work would have cost at API prices.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OverviewWidget", provider: UsageTimelineProvider()) { entry in
            OverviewWidgetView(entry: entry)
                .tint(entry.accent.color)
                .containerBackground(for: .widget) { WidgetCanvas(accent: entry.accent.color) }
        }
        .configurationDisplayName(WidgetStrings.text("Pace and spending"))
        .description(WidgetStrings.text("Session and weekly pace for each provider, with today's and this week's cost."))
        .supportedFamilies([.systemLarge, .systemExtraLarge])   // extra large: iPad only
    }
}

struct OverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var items: [UsageInfo] { entry.items.filter { $0.primary != nil } }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: SoftTheme.Space.sm) {
                BrandWordmark(font: .system(.title3, design: .rounded, weight: .semibold))
                Text(entry.loginRequiredIDs.isEmpty ? WidgetStrings.text("Open AImana to load usage")
                     : WidgetStrings.signInAgain(for: entry.loginRequiredIDs))
                    .softText(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: family == .systemExtraLarge ? SoftTheme.Space.md : SoftTheme.Space.sm) {
                HStack {
                    BrandWordmark(font: .system(.caption, design: .rounded, weight: .bold))
                    Spacer()
                    if let oldest = items.map(\.lastUpdated).min() {
                        Text(WidgetStrings.updated(oldest, relativeTo: entry.date))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    WidgetRefreshButton().padding(.vertical, -6).padding(.trailing, -6)
                }
                .layoutPriority(1)   // header and cost row are sized first; the lanes compress
                if family == .systemExtraLarge {
                    // iPad's extra large widget: up to four providers, two per row.
                    Grid(alignment: .topLeading, horizontalSpacing: SoftTheme.Space.xl,
                         verticalSpacing: SoftTheme.Space.md) {
                        ForEach(Array(stride(from: 0, to: min(items.count, 4), by: 2)), id: \.self) { row in
                            if row > 0 { Divider() }
                            GridRow(alignment: .top) {
                                OverviewProviderBlock(info: items[row], entry: entry)
                                if items.indices.contains(row + 1) {
                                    OverviewProviderBlock(info: items[row + 1], entry: entry)
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                } else {
                    // Large widget: fall back to lanes without pace text when the height runs short.
                    ViewThatFits(in: .vertical) {
                        providerList(showsPace: true, spacing: SoftTheme.Space.sm)
                        providerList(showsPace: false, spacing: SoftTheme.Space.xs)
                    }
                }
                Spacer(minLength: 0)
                OverviewCostRow(items: items, now: entry.date)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func providerList(showsPace: Bool, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { index, info in
                if index > 0 { Divider() }
                OverviewProviderBlock(info: info, entry: entry, style: showsPace ? .inline : .bare)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// How a lane shows its pace: on its own line (iPad), on the title row (iPhone), or not at all (tight fallback).
private enum OverviewLaneStyle { case separateLine, inline, bare }

private struct OverviewProviderBlock: View {
    let info: UsageInfo
    let entry: UsageEntry
    var style: OverviewLaneStyle = .separateLine

    private var lanes: [UsageWindow] {
        [info.window(.session), info.window(.weekly)].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .separateLine ? 10 : (style == .inline ? 8 : 6)) {
            HStack(spacing: SoftTheme.Space.sm) {
                SoftIconBadge(SoftTheme.providerSymbol(info.providerID),
                              tint: SoftTheme.providerTint(info.providerID), size: style == .separateLine ? 22 : 20)
                Text(info.providerName).softText(.body).fontWeight(.semibold).lineLimit(1)
                if let plan = info.plan {
                    Text(plan.capitalized).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if isStale(info, now: entry.date) {
                    Text(WidgetStrings.text("Outdated")).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            ForEach(lanes.isEmpty ? [headline(info)].compactMap { $0 } : lanes, id: \.kind) { window in
                OverviewLane(window: window, entry: entry, style: style)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widgetSummary(info: info, entry: entry))
    }
}

private struct OverviewLane: View {
    @Environment(\.colorScheme) private var scheme
    let window: UsageWindow
    let entry: UsageEntry
    let style: OverviewLaneStyle

    var body: some View {
        let pace = UsagePace(window: window, now: entry.date)
        let status = pace?.status
        // The pace marker is taller than the bar, so lanes need room above and below it.
        VStack(alignment: .leading, spacing: style == .separateLine ? 6 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.xs) {
                Text(window.kind.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                    .font(.system(.caption, design: .rounded, weight: .bold)).monospacedDigit()
                    .foregroundStyle(style == .bare ? statusTint(status) : Color.primary)
                    .layoutPriority(1)
                if style == .inline, status == .depleted, let pace,
                   let text = UsageFormatter.paceText(pace, now: entry.date, compact: true) {
                    Text("· " + text).font(.caption.weight(.semibold)).foregroundStyle(statusTint(status))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                if style == .inline, status == .fast, let pace,
                   let text = UsageFormatter.paceText(pace, now: entry.date, compact: true) {
                    // Fast: the pace replaces the reset countdown; shortened to just "Fast" if it doesn't fit.
                    let parts = text.components(separatedBy: " · ")
                    ViewThatFits(in: .horizontal) {
                        (Text(parts[0]).foregroundStyle(statusTint(status)).fontWeight(.semibold)
                         + Text(parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : "")
                            .foregroundStyle(.secondary))
                        Text(parts[0]).foregroundStyle(statusTint(status)).fontWeight(.semibold)
                    }
                    .font(.caption2).monospacedDigit().lineLimit(1)
                } else if let reset = window.resetsAt, reset > entry.date {
                    Text(UsageFormatter.resetCountdown(to: reset, now: entry.date))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
            OverviewBar(window: window, mode: entry.mode, pace: pace)
            if style == .separateLine, let pace, pace.status == .fast || pace.status == .depleted {
                PaceLine(pace: pace, now: entry.date, compact: true).lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
        }
    }

    private func statusTint(_ status: UsagePace.Status?) -> Color {
        switch status {
        case .fast: SoftTheme.statusTextColor(.warning, scheme: scheme)
        case .depleted: SoftTheme.statusTextColor(.critical, scheme: scheme)
        default: .primary
        }
    }
}

/// A thin track with the pace marker centred on it and overhanging above and below. `UsageBar` lets its
/// 16 pt marker stretch the whole track to 16 pt, which pushed the bar into the next lane here.
private struct OverviewBar: View {
    let window: UsageWindow
    let mode: DisplayMode
    let pace: UsagePace?

    var body: some View {
        let fraction = max(0, min(1, mode.percent(for: window) / 100))
        let severity = UsageSeverity(remainingPercent: window.remainingPercent)
        GeometryReader { proxy in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule().fill(severity.tint).frame(width: fraction * proxy.size.width)
                }
                .overlay(alignment: .leading) {
                    if let pace, pace.status != .depleted {
                        let expected = pace.expectedUsedPercent
                        let marker = max(0, min(1, (mode == .used ? expected : 100 - expected) / 100))
                        Capsule().fill(.primary.opacity(0.75))
                            .frame(width: 2.5, height: 14)
                            .offset(x: marker * proxy.size.width - 1.25)
                    }
                }
        }
        .frame(height: 6)
        .padding(.vertical, 4)   // room for the marker's overhang
    }
}

/// Only shown when the Mac relay published a cost report; the phone cannot compute costs itself.
private struct OverviewCostRow: View {
    let items: [UsageInfo]
    let now: Date

    var body: some View {
        let reports = items.compactMap(\.cost)
        if !reports.isEmpty {
            let day = UsageFormatter.localDayString(for: now)
            let today = reports.reduce(0) { $0 + $1.total(lastDays: 1, endingOn: day).usd }
            let week = reports.reduce(0) { $0 + $1.total(lastDays: 7, endingOn: day).usd }
            HStack(spacing: SoftTheme.Space.lg) {
                OverviewCostCell(title: WidgetStrings.text("Today"), amount: today)
                OverviewCostCell(title: WidgetStrings.text("Last 7 days"), amount: week)
                Spacer(minLength: 0)
            }
            .padding(SoftTheme.Space.sm)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: SoftTheme.innerRadius))
        }
    }
}

private struct OverviewCostCell: View {
    let title: String
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(UsageFormatter.usdText(amount))
                .font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
