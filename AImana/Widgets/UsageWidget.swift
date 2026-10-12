import AImanaCore
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let items: [UsageInfo]
    var mode: DisplayMode = DisplayPreferences.mode()
    var style: DisplayStyle = DisplayPreferences.style()
    var accent: AppearanceAccent = AppearancePreferences.accent()
    /// Providers whose sign-in expired. Only these get a "sign in again" note, and only where they are shown.
    var loginRequiredIDs: Set<String> = WidgetStatusPreferences.loginRequiredProviderIDs()
    var sharedStorageAvailable: Bool = AppGroup.sharedContainerAvailable

    func needsSignIn(_ info: UsageInfo) -> Bool { loginRequiredIDs.contains(info.providerID) }
}

/// Reads the snapshot in the App Group, first letting `WidgetRefresher` fetch a fresh one with the phone's own
/// sign-ins when it is older than the chosen refresh interval.
struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, items: []) }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let items = AppGroup.sharedContainerAvailable ? AppGroup.snapshotStore().load() : []
        completion(UsageEntry(date: .now, items: items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let isPreview = context.isPreview
        let completion = SendableCompletion(handler: completion)
        Task {
            if !isPreview { await WidgetRefresher.refreshIfNeeded() }
            completion(Self.timeline())
        }
    }

    private static func timeline() -> Timeline<UsageEntry> {
        let now = Date()
        let items = AppGroup.sharedContainerAvailable ? AppGroup.snapshotStore().load() : []
        let transitions = items.flatMap { info in
            [info.lastUpdated.addingTimeInterval(3601)] + info.windows.compactMap { $0.resetsAt?.addingTimeInterval(1) }
        }
        let entries = ([now] + transitions.filter { $0 > now }).sorted().map { UsageEntry(date: $0, items: items) }
        // iOS decides the real cadence (and may stretch it); the app also reloads this timeline after each refresh.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(RefreshPreferences.interval().seconds)))
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .tint(entry.accent.color)
                .containerBackground(for: .widget) { WidgetCanvas(accent: entry.accent.color) }
        }
        .configurationDisplayName("AI·mana")
        .description(WidgetStrings.text("Claude Code and OpenAI Codex quota at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// Background for every AImana widget. It must be a View: a `Widget` struct never receives the real
/// colour scheme, so reading it there always yielded the light canvas under white dark-mode text.
struct WidgetCanvas: View {
    @Environment(\.colorScheme) private var scheme
    let accent: Color

    var body: some View {
        SoftTheme.canvas(scheme).overlay(accent.opacity(0.06))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        let usable = entry.items.filter { $0.primary != nil }
        switch family {
        case .accessoryCircular: LockCircularView(entry: entry)
        case .accessoryRectangular: LockRectangularView(entry: entry)
        case .systemMedium:
            if usable.isEmpty { WidgetEmptyView(entry: entry) } else { MediumView(entry: entry) }
        default:
            if usable.isEmpty { WidgetEmptyView(entry: entry) } else { SmallView(entry: entry) }
        }
    }
}

private struct WidgetEmptyView: View {
    let entry: UsageEntry
    var body: some View {
        VStack(spacing: SoftTheme.Space.sm) {
            BrandWordmark(font: .system(.title3, design: .rounded, weight: .semibold))
            Text(!entry.loginRequiredIDs.isEmpty ? WidgetStrings.signInAgain(for: entry.loginRequiredIDs) :
                 WidgetStrings.text(entry.sharedStorageAvailable ? "Open AImana to load usage" : "Shared data unavailable"))
                .softText(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func headline(_ info: UsageInfo) -> UsageWindow? { info.primary }

/// Data older than an hour is flagged rather than shown as if it were current.
func isStale(_ info: UsageInfo, now: Date) -> Bool {
    now.timeIntervalSince(info.lastUpdated) > 3600 || info.windows.contains { $0.isOutdated(now: now) }
}

struct SmallView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: UsageEntry

    private var visibleItems: [UsageInfo] {
        Array(entry.items.filter { $0.primary != nil }.prefix(dynamicTypeSize.isAccessibilitySize ? 1 : 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            HStack(spacing: SoftTheme.Space.xs) {
                BrandWordmark(font: .system(.caption, design: .rounded, weight: .bold))
                Spacer(minLength: 0)
            }
            if entry.style == .rings {
                HStack(alignment: .center, spacing: 5) {
                    ForEach(visibleItems) { info in
                        WidgetRingTile(info: info, entry: entry, size: 52)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
                    ForEach(visibleItems) { info in
                        WidgetQuotaRow(info: info, entry: entry, compact: true)
                    }
                }
            }
            if let oldest = visibleItems.min(by: { $0.lastUpdated < $1.lastUpdated }),
               isStale(oldest, now: entry.date) {
                Text(WidgetStrings.format("Outdated · %@", WidgetStrings.updated(oldest.lastUpdated, relativeTo: entry.date)))
                    .softText(.caption).foregroundStyle(.orange)
                    .lineLimit(2).minimumScaleFactor(0.8)
            } else if case let ids = Set(visibleItems.filter(entry.needsSignIn).map(\.providerID)), !ids.isEmpty {
                Text(WidgetStrings.signInAgain(for: ids)).softText(.caption).foregroundStyle(.orange)
                    .lineLimit(2).minimumScaleFactor(0.8)
            } else if let reset = visibleItems.compactMap({ headline($0)?.resetsAt })
                .filter({ $0 > entry.date }).min() {
                Text(UsageFormatter.resetText(for: reset, now: entry.date) ?? "")
                    .softText(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

struct MediumView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: UsageEntry

    var body: some View {
        HStack(alignment: .top, spacing: SoftTheme.Space.md) {
            ForEach(Array(entry.items.filter { $0.primary != nil }
                .prefix(dynamicTypeSize.isAccessibilitySize ? 1 : 2).enumerated()), id: \.offset) { index, info in
                if index > 0 { Divider() }
                WidgetMediumColumn(info: info, entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            WidgetRefreshButton().offset(x: 6, y: 6)
        }
    }
}

private struct WidgetRingTile: View {
    let info: UsageInfo
    let entry: UsageEntry
    let size: CGFloat

    private var stale: Bool { isStale(info, now: entry.date) }

    var body: some View {
        VStack(spacing: SoftTheme.Space.xs) {
            Text(compactName(info))
                .softText(.caption).fontWeight(.semibold)
                .lineLimit(1)
            if let window = headline(info) {
                if let session = info.window(.session), let weekly = info.window(.weekly) {
                    UsageConcentricRings(session: session, weekly: weekly, mode: entry.mode, size: size)
                } else {
                    UsageRing(window: window, mode: entry.mode, size: size)
                }
                Text(stale ? WidgetStrings.text("Outdated") : entry.mode.caption)
                .softText(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else {
                Text("No quota").softText(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widgetSummary(info: info, entry: entry))
    }
}

private struct WidgetQuotaRow: View {
    let info: UsageInfo
    let entry: UsageEntry
    let compact: Bool

    private var stale: Bool { isStale(info, now: entry.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.xs) {
                Text(compactName(info))
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let window = headline(info) {
                    Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                        .font(.system(size: compact ? 22 : (entry.style == .numbers ? 28 : 19),
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.primary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if entry.style == .bars, let window = headline(info) {
                UsageBar(window: window, mode: entry.mode)
                    .frame(height: 6)
            }
            HStack(spacing: SoftTheme.Space.xs) {
                Text(entry.mode.caption)
                if let window = headline(info), UsageSeverity(remainingPercent: window.remainingPercent) != .normal {
                    Text("· \(statusName(for: window))")
                }
                if stale { Text(WidgetStrings.text("· Outdated")) }
                if !compact, let reset = headline(info)?.resetsAt, reset > entry.date {
                    Spacer(minLength: 2)
                    Text(reset, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widgetSummary(info: info, entry: entry))
    }
}

/// One provider in the medium widget. A systemMedium widget is only about 126–138 pt tall inside its margins, so the
/// column steps down (smaller ring, no plan line) until everything fits instead of clipping the header.
private struct WidgetMediumColumn: View {
    let info: UsageInfo
    let entry: UsageEntry

    private var stale: Bool { isStale(info, now: entry.date) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(ringSize: 76, showsPlan: true)
            column(ringSize: 66, showsPlan: true)
            column(ringSize: 58, showsPlan: false)
            column(ringSize: 46, showsPlan: false)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(widgetSummary(info: info, entry: entry))
    }

    private func column(ringSize: CGFloat, showsPlan: Bool) -> some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
            HStack(spacing: SoftTheme.Space.sm) {
                SoftIconBadge(SoftTheme.providerSymbol(info.providerID),
                              tint: SoftTheme.providerTint(info.providerID), size: 24)
                Text(info.providerName)
                    .softText(.body).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if showsPlan, let plan = info.plan {
                Text(plan.capitalized).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let window = headline(info) {
                if entry.style == .rings {
                    Group {
                        if let session = info.window(.session), let weekly = info.window(.weekly) {
                            UsageConcentricRings(session: session, weekly: weekly, mode: entry.mode, size: ringSize)
                        } else {
                            UsageRing(window: window, mode: entry.mode, size: ringSize)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                            .font(.system(size: entry.style == .numbers ? 33 : 29,
                                          weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(.primary)
                        Text(entry.mode.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if entry.style == .bars {
                        UsageBar(window: window, mode: entry.mode).frame(height: 7)
                    }
                }
                statusRow(window)
            } else {
                Text("No quota").font(.caption).foregroundStyle(.secondary)
            }
            if entry.needsSignIn(info) {
                Text(WidgetStrings.signInAgain(for: [info.providerID]))
                    .softText(.caption).foregroundStyle(.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    /// Badge and reset share one line, so a depleted column is no taller than a normal one.
    @ViewBuilder private func statusRow(_ window: UsageWindow) -> some View {
        let reset = window.resetsAt.flatMap { $0 > entry.date ? $0 : nil }
        if stale {
            Text(WidgetStrings.format("Outdated · %@", WidgetStrings.updated(info.lastUpdated, relativeTo: entry.date)))
                .softText(.caption).foregroundStyle(.orange)
                .lineLimit(1).minimumScaleFactor(0.7)
        } else if window.remainingPercent == 0 || window.remainingPercent < 20 || reset != nil {
            HStack(spacing: SoftTheme.Space.xs) {
                if window.remainingPercent == 0 {
                    Text(WidgetStrings.text("DEPLETED"))
                        .font(.caption2.weight(.bold)).foregroundStyle(.red)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.red.opacity(0.14), in: Capsule())
                } else if window.remainingPercent < 20 && reset == nil {
                    Text(WidgetStrings.text("Approaching limit"))
                        .font(.caption2.weight(.medium)).foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else if window.remainingPercent < 20 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                if let reset {
                    // Icon plus countdown: "Resets in 4h 39min" did not fit a medium column.
                    ResetCountdown(reset: reset, now: entry.date)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

struct LockCircularView: View {
    let entry: UsageEntry

    var body: some View {
        if let info = entry.items.first(where: { headline($0) != nil }), let window = headline(info) {
            if entry.style == .rings {
                Gauge(value: entry.mode.percent(for: window), in: 0...100) {
                    // The provider's glyph: a name like "Claude" collided with the value in the small circle.
                    if isStale(info, now: entry.date) {
                        Text(WidgetStrings.text("Old"))
                    } else {
                        Image(systemName: SoftTheme.providerSymbol(info.providerID))
                    }
                } currentValueLabel: {
                    Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(UsageSeverity(remainingPercent: window.remainingPercent).tint)
                .accessibilityLabel(widgetSummary(info: info, entry: entry))
            } else {
                VStack(spacing: 2) {
                    Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    if entry.style == .bars {
                        UsageBar(window: window, mode: entry.mode).frame(width: 36, height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(widgetSummary(info: info, entry: entry))
            }
        } else {
            Text(entry.loginRequiredIDs.isEmpty ? "—" : WidgetStrings.text("Login"))
                .accessibilityLabel(entry.loginRequiredIDs.isEmpty ? WidgetStrings.text("No quota available")
                                    : WidgetStrings.signInAgain(for: entry.loginRequiredIDs))
        }
    }
}

struct LockRectangularView: View {
    let entry: UsageEntry

    var body: some View {
        if let info = entry.items.first(where: { headline($0) != nil }), let window = headline(info) {
            HStack(spacing: 7) {
                if entry.style == .rings {
                    Gauge(value: entry.mode.percent(for: window), in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(UsageSeverity(remainingPercent: window.remainingPercent).tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactName(info)).font(.headline)
                        Text(window.kind.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        if let reset = window.resetsAt, reset > entry.date, !isStale(info, now: entry.date) {
                            ResetCountdown(reset: reset, now: entry.date, font: .caption2)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactName(info)).font(.caption2.weight(.semibold))
                        Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    if entry.style == .bars {
                        UsageBar(window: window, mode: entry.mode).frame(width: 28, height: 5)
                    }
                }
                if isStale(info, now: entry.date) {
                    Text(WidgetStrings.updated(info.lastUpdated, relativeTo: entry.date))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(widgetSummary(info: info, entry: entry))
        } else {
            Text(entry.loginRequiredIDs.isEmpty ? WidgetStrings.text("AImana · No quota")
                 : entry.loginRequiredIDs.isDisjoint(with: WidgetStrings.phoneSignInProviderIDs)
                 ? WidgetStrings.text("Sign in on your computer") : WidgetStrings.text("Sign in again"))
                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

func compactName(_ info: UsageInfo) -> String {
    switch info.providerID {
    case "claude": "Claude"
    case "codex": "Codex"
    default: info.providerName
    }
}

private func statusName(for window: UsageWindow) -> String {
    switch UsageSeverity(remainingPercent: window.remainingPercent) {
    case .normal: WidgetStrings.text("Available")
    case .warning: WidgetStrings.text("Low")
    case .critical: WidgetStrings.text("Critical")
    }
}

func widgetSummary(info: UsageInfo, entry: UsageEntry) -> String {
    guard let window = headline(info) else {
        return WidgetStrings.format("%@, no quota available", info.providerName)
    }
    let value = UsageFormatter.percentText(entry.mode.percent(for: window))
    let severity = UsageSeverity(remainingPercent: window.remainingPercent)
    var parts = [info.providerName, "\(value) \(entry.mode.caption)", severity.statusText]
    if isStale(info, now: entry.date) {
        parts.append(WidgetStrings.format("Outdated · %@",
                                          WidgetStrings.updated(info.lastUpdated, relativeTo: entry.date)))
    }
    if let reset = UsageFormatter.resetText(for: window.resetsAt, now: entry.date) {
        parts.append(reset)
    }
    return parts.joined(separator: ", ")
}

/// "↻ 4h 39min": the time to the next reset, short enough for medium columns and Lock Screen widgets.
struct ResetCountdown: View {
    let reset: Date
    let now: Date
    var font: Font = .system(.caption, design: .rounded)

    var body: some View {
        Label {
            Text(UsageFormatter.resetCountdown(to: reset, now: now)).monospacedDigit()
        } icon: {
            Image(systemName: "arrow.clockwise")
        }
        .labelStyle(.titleAndIcon)
        .font(font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityLabel(UsageFormatter.resetText(for: reset, now: now) ?? "")
    }
}
