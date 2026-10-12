import AImanaCore
import SwiftUI

/// The watch's one screen: per provider, session and weekly rings, the session pace, resets and how old the
/// reading is. Everything comes from the iPhone; nothing here fetches.
struct WatchDashboardView: View {
    let state: WatchState

    var body: some View {
#if DEBUG
        if UserDefaults.standard.bool(forKey: "AImanaWatchGallery") {
            ComplicationGallery(payload: state.payload)
        } else {
            dashboard
        }
#else
        dashboard
#endif
    }

    /// Inside a NavigationStack so the scroll content starts below the system clock instead of under it.
    private var dashboard: some View {
        NavigationStack { dashboardContent }
    }

    private var dashboardContent: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
                        header(now: context.date)
                        if let payload = state.payload, !payload.providers.isEmpty {
                            ForEach(payload.providers) { provider in
                                ProviderCard(provider: provider, mode: payload.mode, now: context.date)
                                    .id(provider.id)
                            }
                        } else {
                            emptyState
                        }
                        if !WatchState.isDemo { refreshButton.id("refresh") }
                    }
                    .padding(.horizontal, SoftTheme.Space.xs)
                }
#if DEBUG
                // Simulator screenshots (`-AImanaWatchScrollTo codex|refresh`): the simulator has no scripted crown.
                .onAppear {
                    if let target = UserDefaults.standard.string(forKey: "AImanaWatchScrollTo") {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
#endif
            }
        }
        .containerBackground(SoftTheme.ink.gradient, for: .navigation)
        .preferredColorScheme(.dark)
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BrandWordmark(font: .system(.title3, design: .rounded, weight: .bold))
            if let updated = state.payload?.oldestUpdate {
                let stale = now.timeIntervalSince(updated) > WatchFreshness.staleAfter
                Label {
                    Text(WatchStrings.updated(updated, now: now))
                } icon: {
                    Image(systemName: stale ? "clock.badge.exclamationmark" : "clock")
                }
                .font(.caption2)
                .foregroundStyle(stale ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
            Text(WatchStrings.text("No usage yet")).font(.headline)
            Text(WatchStrings.text("Open AI·mana on your iPhone to send your usage to the watch."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SoftTheme.Space.md)
        .softSurface(radius: SoftTheme.innerRadius)
    }

    private var refreshButton: some View {
        VStack(spacing: 2) {
            Button {
                state.requestFromPhone()
            } label: {
                HStack {
                    if state.isRequesting { ProgressView().frame(width: 18, height: 18) }
                    else { Image(systemName: "iphone.and.arrow.forward") }
                    Text(WatchStrings.text("Update from iPhone"))
                }
            }
            .disabled(state.isRequesting)
            if state.requestFailed {
                Text(WatchStrings.text("iPhone not reachable"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderCard: View {
    let provider: WatchPayload.Provider
    let mode: DisplayMode
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
            HStack(spacing: SoftTheme.Space.xs) {
                Image(systemName: SoftTheme.providerSymbol(provider.id))
                    .font(.caption)
                    .foregroundStyle(SoftTheme.providerTint(provider.id))
                Text(provider.name)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: SoftTheme.Space.sm) {
                rings
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    ForEach(Array(provider.lanes.prefix(2).enumerated()), id: \.offset) { _, lane in
                        LaneRow(window: lane.window, mode: mode, now: now)
                    }
                }
            }
            if let pace = sessionPace {
                PaceLine(pace: pace, now: now, compact: true)
            }
            if let issue = provider.issue {
                Label(issue == .signIn ? WatchStrings.signInLocation : WatchStrings.text("Showing the last reading"),
                      systemImage: issue == .signIn ? "person.crop.circle.badge.exclamationmark" : "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let updated = provider.updatedAt, now.timeIntervalSince(updated) > WatchFreshness.staleAfter {
                Label(WatchStrings.updated(updated, now: now), systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(SoftTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softSurface(tint: SoftTheme.providerTint(provider.id), radius: SoftTheme.innerRadius + 4)
    }

    /// No projection from an old reading: the rate it implies may no longer hold.
    private var sessionPace: UsagePace? {
        guard let session = provider.session, let updated = provider.updatedAt,
              now.timeIntervalSince(updated) <= WatchFreshness.staleAfter else { return nil }
        return UsagePace(window: session, now: now)
    }

    @ViewBuilder private var rings: some View {
        if let session = provider.session, let weekly = provider.weekly {
            UsageConcentricRings(session: session, weekly: weekly, mode: mode, size: 62,
                                 sessionPace: sessionPace)
        } else if let primary = provider.primary {
            UsageRing(window: primary, mode: mode, size: 62)
        }
    }
}

private struct LaneRow: View {
    let window: UsageWindow
    let mode: DisplayMode
    let now: Date

    private var name: String {
        switch window.kind {
        case .session: CoreStrings.text("Session")
        case .weekly: CoreStrings.text("Weekly")
        default: window.kind.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.xs) {
                Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(UsageFormatter.percentText(mode.percent(for: window)))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(UsageSeverity(remainingPercent: window.remainingPercent) == .normal
                                     ? AnyShapeStyle(.primary)
                                     : AnyShapeStyle(UsageSeverity(remainingPercent: window.remainingPercent).tint))
            }
            if let reset = resetText {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resetText: String? {
        guard let resetsAt = window.resetsAt else { return nil }
        if resetsAt <= now { return CoreStrings.text("Reset passed") }
        return "↻ " + UsageFormatter.resetCountdown(to: resetsAt, now: now)
    }
}

#if DEBUG
/// Simulator aid (`-AImanaWatchGallery YES`): the complication views at roughly their face sizes, for screenshots.
/// Faces render them tinted and clipped; this shows layout and copy, not the exact face rendering.
private struct ComplicationGallery: View {
    let payload: WatchPayload?

    var body: some View {
        let content = ComplicationContent(date: .now, payload: payload)
        ScrollView {
            VStack(spacing: SoftTheme.Space.md) {
                HStack(spacing: SoftTheme.Space.md) {
                    CircularComplication(content: content).frame(width: 50, height: 50)
                    CornerPreview(content: content)
                }
                RectangularComplication(content: content)
                    .frame(width: 178, height: 58)
                    .padding(4)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                InlineComplication(content: content)
                    .font(.footnote)
                    .frame(width: 184)
                    .lineLimit(1)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The corner family's main text plus its gauge laid flat (the face curves it along the bezel).
private struct CornerPreview: View {
    let content: ComplicationContent

    var body: some View {
        VStack(spacing: 2) {
            Text(content.percentText)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
            Gauge(value: content.value ?? 0, in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            } minimumValueLabel: {
                Text(Image(systemName: SoftTheme.providerSymbol(content.provider?.id ?? "")))
            } maximumValueLabel: {
                Text(content.resetCountdown ?? "")
            }
            .gaugeStyle(.accessoryLinear)
            .tint(content.severity?.tint ?? .gray)
            .font(.caption2)
        }
        .frame(width: 110)
    }
}

#Preview("Sample") {
    WatchDashboardView(state: WatchState.shared)
}
#endif
