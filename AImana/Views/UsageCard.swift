import AImanaCore
import SwiftUI

struct UsageCard: View {
    @Environment(\.colorScheme) private var scheme
    let state: ProviderState
    let mode: DisplayMode
    let style: DisplayStyle
    let showChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            header
            if let usage = state.usage {
                // Re-evaluate countdowns every minute without refetching.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                        if usage.windows.isEmpty {
                            // Balance-only providers (DeepSeek, Moonshot, xAI): no lane area at all.
                            BalanceContent(details: usage.details)
                        } else {
                            if style == .rings,
                               let session = usage.window(.session),
                               let weekly = usage.window(.weekly) {
                                ConcentricCardContent(usage: usage, session: session, weekly: weekly,
                                                      mode: mode, now: context.date)
                            } else {
                                ForEach(Array(usage.windows.enumerated()), id: \.offset) { index, window in
                                    if index > 0 { Divider() }
                                    WindowRow(window: window, mode: mode, style: style,
                                              now: context.date, isHeadline: window == usage.primary,
                                              budget: DailyBudget(window: window, history: usage.history,
                                                                  providerID: usage.providerID, now: context.date))
                                }
                            }
                            if !usage.details.isEmpty {
                                Divider()
                                DetailsList(details: usage.details)
                            }
                        }
                        if let cost = usage.cost {
                            let today = UsageFormatter.localDayString(for: context.date)
                            let todayUSD = UsageFormatter.usdText(cost.total(lastDays: 1, endingOn: today).usd)
                            let monthUSD = UsageFormatter.usdText(cost.total(lastDays: 30, endingOn: today).usd)
                            Text(AppStrings.format("Today %@ · 30d %@ est.", todayUSD, monthUSD))
                                .softText(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel(AppStrings.format("Estimated cost today %@, last 30 days %@", todayUSD, monthUSD))
                        }
                        SnapshotStatus(usage: usage, now: context.date)
                    }
                }
            }
            if let error = state.error {
                ErrorBanner(error: error, hasData: state.usage != nil, providerID: state.providerID)
            }
        }
        .padding(SoftTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softSurface(tint: SoftTheme.providerTint(state.providerID))
        .fontDesign(.rounded)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SoftTheme.Space.md) {
            SoftIconBadge(SoftTheme.providerSymbol(state.providerID),
                          tint: SoftTheme.providerTint(state.providerID), size: 28)
            Text(state.displayName).softText(.headline)
            Spacer()
            if state.usage?.windows.contains(where: { $0.remainingPercent == 0 }) == true
                || state.usage?.details.contains(where: \.isExhaustedBalance) == true {
                Text(AppStrings.text("DEPLETED"))
                    .softText(.caption).fontWeight(.bold)
                    .foregroundStyle(SoftTheme.statusTextColor(.critical, scheme: scheme))
                    .padding(.horizontal, SoftTheme.Space.sm).padding(.vertical, SoftTheme.Space.xs)
                    .background(.red.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Quota depleted")
            }
            if let plan = state.usage?.plan {
                Text(plan.capitalized).softText(.caption).fontWeight(.semibold)
                    .padding(.horizontal, SoftTheme.Space.sm).padding(.vertical, SoftTheme.Space.xs)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

/// Compact ring layout: small concentric rings on the left, one block of numbers per window on the right,
/// so both providers fit on one iPhone screen.
private struct ConcentricCardContent: View {
    let usage: UsageInfo
    let session: UsageWindow
    let weekly: UsageWindow
    let mode: DisplayMode
    let now: Date
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            HStack(spacing: SoftTheme.Space.lg) {
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    Text(session.kind.title).softText(.caption).foregroundStyle(.secondary)
                    Text(UsageFormatter.percentText(mode.percent(for: session)))
                        .softText(.hero).monospacedDigit().minimumScaleFactor(0.75)
                    Text(mode.caption).softText(.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: SoftTheme.Space.xs)
                UsageConcentricRings(session: session, weekly: weekly, mode: mode, size: ringSize,
                                     sessionPace: UsagePace(window: session, now: now), showsCenterValue: false)
            }
            if let pace = UsagePace(window: session, now: now), pace.status != .tooEarly {
                PaceLine(pace: pace, now: now, compact: true)
            }
            if let reset = UsageFormatter.resetText(for: session.resetsAt, now: now) {
                Text(reset).softText(.caption).foregroundStyle(.secondary)
            }
            ForEach(usage.windows.filter { $0.kind != .session }, id: \.kind) { window in
                Divider()
                WindowSummary(window: window, mode: mode, now: now,
                              budget: DailyBudget(window: window, history: usage.history,
                                                  providerID: usage.providerID, now: now))
            }
        }
    }
}

private struct WindowSummary: View {
    let window: UsageWindow
    let mode: DisplayMode
    let now: Date
    let budget: DailyBudget?

    private var valueText: String { UsageFormatter.percentText(mode.percent(for: window)) }
    private var pace: UsagePace? { UsagePace(window: window, now: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.xs) {
                    Text(window.kind.title).softText(.body).fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Text("\(valueText) \(mode.caption)")
                        .softText(.body).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(.primary)
                }
                if let pace, pace.status != .tooEarly {
                    PaceLine(pace: pace, now: now, compact: true)
                }
                if let text = UsageFormatter.resetText(for: window.resetsAt, now: now) {
                    Text(text).softText(.caption).foregroundStyle(.secondary)
                }
                BudgetCaption(budget: budget)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Daily budget 15%/day · today 6%" under multi-day lanes; silent when depleted or outdated
/// (the row already says so).
private struct BudgetCaption: View {
    let budget: DailyBudget?

    var body: some View {
        if let budget, budget.status == .spread || budget.status == .lastDay {
            Text(AppStrings.format("Daily budget %@", budget.compactText()))
                .softText(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// Balance-only providers: the first balance as the headline, any other currencies below it.
private struct BalanceContent: View {
    @Environment(\.colorScheme) private var scheme
    let details: [UsageDetail]

    var body: some View {
        if let first = details.first {
            VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    Text(first.title).softText(.caption).foregroundStyle(.secondary)
                    Text(first.summary())
                        .softText(.title).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let caption = first.caption() {
                        Text(caption).softText(.caption).fontWeight(.medium)
                            .foregroundStyle(first.isExhaustedBalance
                                             ? SoftTheme.statusTextColor(.critical, scheme: scheme) : .secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if details.count > 1 {
                    Divider()
                    DetailsList(details: Array(details.dropFirst()))
                }
            }
        } else {
            Text("No balance reported.").softText(.body).foregroundStyle(.secondary)
        }
    }
}

/// Credits and reset credits reported next to the rate-limit windows.
private struct DetailsList: View {
    let details: [UsageDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            ForEach(details) { detail in
                HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                    Text(detail.title).softText(.caption).fontWeight(.semibold)
                    Spacer(minLength: SoftTheme.Space.xs)
                    Text(detail.summary())
                        .softText(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SnapshotStatus: View {
    let usage: UsageInfo
    let now: Date

    private var outdated: Bool {
        now.timeIntervalSince(usage.lastUpdated) > 3600 || usage.windows.contains { $0.isOutdated(now: now) }
    }

    var body: some View {
        HStack(spacing: SoftTheme.Space.xs) {
            Text(AppStrings.updated(usage.lastUpdated, relativeTo: now))
            if outdated {
                Text(AppStrings.text("· Outdated")).foregroundStyle(.orange)
            }
        }
        .softText(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct WindowRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let window: UsageWindow
    let mode: DisplayMode
    let style: DisplayStyle
    let now: Date
    let isHeadline: Bool
    let budget: DailyBudget?

    private var severity: UsageSeverity { UsageSeverity(remainingPercent: window.remainingPercent) }
    private var valueText: String { UsageFormatter.percentText(mode.percent(for: window)) }
    private var pace: UsagePace? { UsagePace(window: window, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            switch style {
            case .bars: bars
            case .rings: rings
            case .numbers: numbers
            }
            if window.isOutdated(now: now) {
                Text(AppStrings.text("Reset passed, refresh for current value"))
                    .softText(.caption).foregroundStyle(.secondary)
            } else if let text = UsageFormatter.resetText(for: window.resetsAt, now: now) {
                Text(text).softText(.caption).foregroundStyle(.secondary)
            }
            BudgetCaption(budget: budget)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rowHeader: some View {
        Group {
            if isHeadline {
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    Text(window.kind.title).softText(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                        Text(valueText).softText(.hero).monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .smooth, value: valueText)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(mode.caption).softText(.body).foregroundStyle(.secondary)
                    }
                }
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                        Text(window.kind.title).softText(.body).fontWeight(.semibold)
                        Text("\(valueText) \(mode.caption)").softText(.headline).monospacedDigit()
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.sm) {
                        Text(window.kind.title).softText(.body).fontWeight(.semibold)
                        Spacer(minLength: SoftTheme.Space.xs)
                        Text("\(valueText) \(mode.caption)")
                            .softText(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            rowHeader
            UsageBar(window: window, mode: mode, pace: pace)
            statusLine
        }
    }

    private var rings: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            rowHeader
            HStack(spacing: SoftTheme.Space.lg) {
                UsageRing(window: window, mode: mode, size: isHeadline ? 72 : 56)
                statusLine
                Spacer(minLength: 0)
            }
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            rowHeader
            if isHeadline {
                HStack(spacing: SoftTheme.Space.lg) {
                    Gauge(value: mode.percent(for: window), in: 0...100) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(severity.tint)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    statusLine
                    Spacer(minLength: 0)
                }
            } else {
                Gauge(value: mode.percent(for: window), in: 0...100) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(severity.tint)
                    .accessibilityHidden(true)
                statusLine
            }
        }
    }

    /// Pace when there is enough signal; otherwise the plain low-quota warning.
    @ViewBuilder private var statusLine: some View {
        if let pace, pace.status != .tooEarly {
            PaceLine(pace: pace, now: now)
        } else {
            warningLabel
        }
    }

    @ViewBuilder private var warningLabel: some View {
        if severity != .normal {
            Label {
                Text(severity.statusText)
            } icon: {
                Image(systemName: severity == .critical ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                    // Pulses twice, then rests: an endless pulse keeps the screen redrawing and costs battery.
                    .symbolEffect(.pulse, options: .repeat(2), isActive: !reduceMotion)
            }
                .softText(.caption).fontWeight(.medium)
                .foregroundStyle(SoftTheme.statusTextColor(severity, scheme: scheme))
        }
    }

    private var accessibilitySummary: String {
        var parts = [window.kind.title, "\(valueText) \(mode.caption)", severity.statusText]
        if window.isOutdated(now: now) {
            parts.append(AppStrings.text("Reset passed, refresh for current value"))
        } else if let reset = UsageFormatter.resetText(for: window.resetsAt, now: now) {
            parts.append(reset)
        }
        if let budget, budget.status == .spread || budget.status == .lastDay {
            parts.append(AppStrings.format("Daily budget %@", budget.compactText()))
        }
        return parts.joined(separator: ", ")
    }
}

private struct ErrorBanner: View {
    let error: UsageProviderError
    let hasData: Bool
    let providerID: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .softText(.caption)
            .foregroundStyle(.orange)
    }

    private var message: String {
        let stale = hasData ? " " + AppStrings.text("Showing last known data.") : ""
        switch error {
        case .unauthenticated:
            if APIKeyProvider.isAPIKeyProvider(providerID) {
                return AppStrings.text("The saved key was not accepted. Replace it in Settings → More providers.")
            }
            return AppStrings.text("Sign in again on your Mac (Claude Code / Codex), then refresh.")
        case .relayUnavailable: return AppStrings.text("Mac relay file not found. Open Settings to connect it.") + stale
        case .rateLimited(let until):
            if let until { return AppStrings.format("Rate limited until %@.", until.formatted(date: .omitted, time: .shortened)) + stale }
            return AppStrings.text("Rate limited.") + stale
        case .decoding: return AppStrings.text("Unexpected response from the provider.") + stale
        case .network: return AppStrings.text("Network problem.") + stale
        case .server(let status): return AppStrings.format("Provider error (HTTP %d).", status) + stale
        }
    }
}
