import AImanaCore
import SwiftUI
import WidgetKit

/// What one complication shows at one moment. Built from the payload the iPhone last sent.
struct ComplicationContent {
    let date: Date
    let payload: WatchPayload?

    /// The provider with the fullest headline lane: the one worth a glance.
    var provider: WatchPayload.Provider? { payload?.busiest(at: date) ?? payload?.providers.first }
    var window: UsageWindow? { provider?.primary }
    var mode: DisplayMode { payload?.mode ?? .used }
    var value: Double? { window.map { mode.percent(for: $0) } }
    var percentText: String { value.map(UsageFormatter.percentText) ?? "—" }
    var severity: UsageSeverity? { window.map { UsageSeverity(remainingPercent: $0.remainingPercent) } }
    var isStale: Bool { provider.map { WatchFreshness.isStale($0, now: date) } ?? true }
    var needsSignIn: Bool { provider?.issue == .signIn }

    /// "2h 10m", or nil when there is no reset or it already passed.
    var resetCountdown: String? {
        guard let resetsAt = window?.resetsAt, resetsAt > date else { return nil }
        return UsageFormatter.resetCountdown(to: resetsAt, now: date)
    }

    /// Reading age, only once it is worth mentioning (15 minutes or more).
    var ageText: String? {
        guard let updated = provider?.updatedAt, date.timeIntervalSince(updated) >= 15 * 60 else { return nil }
        return WatchStrings.age(of: updated, now: date)
    }

    var accessibilitySummary: String {
        guard let provider, window != nil else { return WatchStrings.text("No usage yet") }
        var parts = ["\(provider.name) \(percentText) \(mode.caption)"]
        if let resetText = UsageFormatter.resetText(for: window?.resetsAt, now: date) { parts.append(resetText) }
        if let updated = provider.updatedAt { parts.append(WatchStrings.updated(updated, now: date)) }
        return parts.joined(separator: ", ")
    }
}

/// Session gauge with the provider's glyph; a clock replaces the glyph when the reading is old.
struct CircularComplication: View {
    let content: ComplicationContent

    var body: some View {
        Gauge(value: content.value ?? 0, in: 0...100) {
            Image(systemName: content.isStale ? "clock" : SoftTheme.providerSymbol(content.provider?.id ?? ""))
        } currentValueLabel: {
            Text(content.value.map { String(format: "%.0f", min(100, max(0, $0))) } ?? "—")
                .font(.system(.body, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .tint(content.severity?.tint ?? .gray)
        .opacity(content.isStale ? 0.6 : 1)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilitySummary)
    }
}

/// Provider and percent, a capacity bar, then the reset countdown and (when old) the reading's age.
struct RectangularComplication: View {
    let content: ComplicationContent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: SoftTheme.providerSymbol(content.provider?.id ?? ""))
                    .font(.caption2)
                Text(content.provider?.name ?? "AI·mana")
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(content.percentText)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .widgetAccentable()
            Gauge(value: content.value ?? 0, in: 0...100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(content.severity?.tint ?? .gray)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(content.isStale ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilitySummary)
    }

    private var detail: String {
        if content.window == nil {
            return content.needsSignIn ? WatchStrings.signInLocation : WatchStrings.text("Open AI·mana on your iPhone")
        }
        var parts: [String] = []
        if let countdown = content.resetCountdown {
            parts.append("↻ " + countdown)
        } else if content.window?.isOutdated(now: content.date) == true {
            parts.append(CoreStrings.text("Reset passed"))
        }
        if content.needsSignIn { parts.append(WatchStrings.shortSignInLocation) }
        if let age = content.ageText { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

/// The percent in the corner, with a curved gauge along the bezel.
struct CornerComplication: View {
    let content: ComplicationContent

    var body: some View {
        Text(content.percentText)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: content.value ?? 0, in: 0...100) {
                    Text(content.provider?.name ?? "AI·mana")
                } currentValueLabel: {
                    Text(content.percentText)
                } minimumValueLabel: {
                    Text(Image(systemName: content.isStale ? "clock" : SoftTheme.providerSymbol(content.provider?.id ?? "")))
                } maximumValueLabel: {
                    Text(content.resetCountdown ?? "")
                }
                .tint(content.severity?.tint ?? .gray)
            }
            .accessibilityLabel(content.accessibilitySummary)
    }
}

/// One line: "✦ Claude Code 42% · 2h 10m" (plus the age when old).
struct InlineComplication: View {
    let content: ComplicationContent

    var body: some View {
        ViewThatFits {
            Text(line(name: content.provider?.name))
            Text(line(name: nil))
        }
        .accessibilityLabel(content.accessibilitySummary)
    }

    private func line(name: String?) -> String {
        guard content.window != nil else { return "AI·mana —" }
        var parts = [[name, content.percentText].compactMap { $0 }.joined(separator: " ")]
        if let countdown = content.resetCountdown { parts.append(countdown) }
        if let age = content.ageText { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let content: ComplicationContent

    var body: some View {
        switch family {
        case .accessoryRectangular: RectangularComplication(content: content)
        case .accessoryCorner: CornerComplication(content: content)
        case .accessoryInline: InlineComplication(content: content)
        default: CircularComplication(content: content)
        }
    }
}
