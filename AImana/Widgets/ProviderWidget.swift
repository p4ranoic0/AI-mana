import AImanaCore
import AppIntents
import SwiftUI
import WidgetKit

enum WidgetProvider: String, AppEnum {
    case claude, codex

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let caseDisplayRepresentations: [WidgetProvider: DisplayRepresentation] = [
        .claude: "Claude Code",
        .codex: "OpenAI Codex",
    ]
}

struct SelectProviderIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider"
    static let description = IntentDescription("Choose which quota this widget shows.")

    @Parameter(title: "Provider", default: .claude)
    var provider: WidgetProvider
}

struct ProviderEntry: TimelineEntry {
    let date: Date
    let providerID: String
    let info: UsageInfo?
    var mode: DisplayMode = DisplayPreferences.mode()
    var accent: AppearanceAccent = AppearancePreferences.accent()
    var loginRequiredIDs: Set<String> = WidgetStatusPreferences.loginRequiredProviderIDs()

    /// Only this widget's own provider counts: another provider's expired login is not this widget's problem.
    var loginRequired: Bool { loginRequiredIDs.contains(providerID) }
}

struct ProviderTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProviderEntry {
        ProviderEntry(date: .now, providerID: "claude", info: nil)
    }

    func snapshot(for configuration: SelectProviderIntent, in context: Context) async -> ProviderEntry {
        entry(for: configuration.provider.rawValue, at: .now)
    }

    func timeline(for configuration: SelectProviderIntent, in context: Context) async -> Timeline<ProviderEntry> {
        if !context.isPreview { await WidgetRefresher.refreshIfNeeded() }
        let now = Date()
        let first = entry(for: configuration.provider.rawValue, at: now)
        let transitions = first.info.map { info in
            [info.lastUpdated.addingTimeInterval(3601)] + info.windows.compactMap { $0.resetsAt?.addingTimeInterval(1) }
        } ?? []
        let entries = [first] + transitions.filter { $0 > now }.sorted().map {
            ProviderEntry(date: $0, providerID: first.providerID, info: first.info)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(RefreshPreferences.interval().seconds)))
    }

    private func entry(for providerID: String, at date: Date) -> ProviderEntry {
        let items = AppGroup.sharedContainerAvailable ? AppGroup.snapshotStore().load() : []
        return ProviderEntry(date: date, providerID: providerID, info: items.first { $0.providerID == providerID })
    }
}

/// One provider in depth: concentric session/weekly rings, pace and the next reset.
struct ProviderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProviderWidget", intent: SelectProviderIntent.self,
                               provider: ProviderTimelineProvider()) { entry in
            ProviderWidgetView(entry: entry)
                .tint(entry.accent.color)
                .containerBackground(for: .widget) { WidgetCanvas(accent: entry.accent.color) }
        }
        .configurationDisplayName(WidgetStrings.text("Provider"))
        .description(WidgetStrings.text("One provider's session and weekly quota, with pace."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProviderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProviderEntry

    var body: some View {
        if let info = entry.info, info.primary != nil {
            if family == .systemMedium {
                ProviderMediumView(info: info, entry: entry)
                    .overlay(alignment: .topTrailing) {
                        WidgetRefreshButton().offset(x: 6, y: -4)
                    }
            } else {
                ProviderSmallView(info: info, entry: entry)
            }
        } else {
            VStack(spacing: SoftTheme.Space.sm) {
                SoftIconBadge(SoftTheme.providerSymbol(entry.providerID),
                              tint: SoftTheme.providerTint(entry.providerID), size: 30)
                Text(entry.loginRequired ? WidgetStrings.signInAgain(for: [entry.providerID])
                     : WidgetStrings.text("Open AImana to load usage"))
                    .softText(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProviderHeader: View {
    let info: UsageInfo

    var body: some View {
        HStack(spacing: SoftTheme.Space.xs) {
            SoftIconBadge(SoftTheme.providerSymbol(info.providerID),
                          tint: SoftTheme.providerTint(info.providerID), size: 20)
            Text(compactName(info)).softText(.caption).fontWeight(.semibold).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct ProviderRings: View {
    let info: UsageInfo
    let entry: ProviderEntry
    let size: CGFloat

    var body: some View {
        if let session = info.window(.session), let weekly = info.window(.weekly) {
            UsageConcentricRings(session: session, weekly: weekly, mode: entry.mode, size: size,
                                 sessionPace: UsagePace(window: session, now: entry.date))
        } else if let window = headline(info) {
            UsageRing(window: window, mode: entry.mode, size: size)
        }
    }
}

struct ProviderSmallView: View {
    let info: UsageInfo
    let entry: ProviderEntry

    var body: some View {
        VStack(spacing: SoftTheme.Space.xs) {
            ProviderHeader(info: info)
            ProviderRings(info: info, entry: entry, size: 86)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ProviderFootnote(info: info, entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(providerSummary(info: info, entry: entry))
    }
}

struct ProviderMediumView: View {
    let info: UsageInfo
    let entry: ProviderEntry

    var body: some View {
        HStack(spacing: SoftTheme.Space.lg) {
            ProviderRings(info: info, entry: entry, size: 112)
            VStack(alignment: .leading, spacing: 10) {
                ProviderHeader(info: info)
                ForEach([UsageWindow.Kind.session, .weekly], id: \.self) { kind in
                    if let window = info.window(kind) {
                        ProviderLane(window: window, entry: entry)
                    }
                }
                Spacer(minLength: 0)
                ProviderFootnote(info: info, entry: entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(providerSummary(info: info, entry: entry))
    }
}

private struct ProviderLane: View {
    let window: UsageWindow
    let entry: ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(UsageFormatter.percentText(entry.mode.percent(for: window)))
                    .font(.system(.caption, design: .rounded, weight: .bold)).monospacedDigit()
            }
            UsageBar(window: window, mode: entry.mode, pace: UsagePace(window: window, now: entry.date))
                .frame(height: 6)
        }
    }
}

/// Outdated beats an expired sign-in beats pace beats reset: the most useful single line for a glance.
private struct ProviderFootnote: View {
    let info: UsageInfo
    let entry: ProviderEntry

    var body: some View {
        if isStale(info, now: entry.date) {
            Text(WidgetStrings.format("Outdated · %@", WidgetStrings.updated(info.lastUpdated, relativeTo: entry.date)))
                .softText(.caption).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
        } else if entry.loginRequired {
            Text(WidgetStrings.signInAgain(for: [entry.providerID]))
                .softText(.caption).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
        } else if let session = info.window(.session) ?? headline(info),
                  let pace = UsagePace(window: session, now: entry.date),
                  pace.status == .fast || pace.status == .depleted {
            // "Runs out in 3h 33min" fits a small widget; the full pace line ("Fast · runs out in …") did not.
            Label {
                Text(pace.exhaustsAt.map { WidgetStrings.format("Runs out in %@", UsageFormatter.resetCountdown(to: $0, now: entry.date)) }
                     ?? WidgetStrings.text("Depleted"))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .softText(.caption).foregroundStyle(.orange)
            .lineLimit(1).minimumScaleFactor(0.8)
        } else if let text = UsageFormatter.resetText(for: headline(info)?.resetsAt, now: entry.date) {
            Text(text).softText(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

private func providerSummary(info: UsageInfo, entry: ProviderEntry) -> String {
    widgetSummary(info: info, entry: UsageEntry(date: entry.date, items: [info], mode: entry.mode))
}
