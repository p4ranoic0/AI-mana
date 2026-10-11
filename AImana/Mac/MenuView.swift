import AImanaCore
import AppKit
import RelayKit
import SwiftUI

struct MenuView: View {
    @Bindable var controller: RelayController
    @Environment(\.openSettings) private var openSettings
    @State private var expandedProviders: [String: Bool] =
        UserDefaults.standard.dictionary(forKey: "menu.expandedProviders")?.compactMapValues { $0 as? Bool } ?? [:]

    private var providerIDs: [String] { ["claude", "codex"] + controller.enabledOptionalProviders }

    /// Give the scroll area room for compact rows, then cap it when expanded lanes would make the menu too tall.
    private var providerContentHeight: CGFloat {
        providerIDs.reduce(0) { height, id in
            let entry = controller.entry(id)
            let usage = entry?.usage
            let headline = usage?.windows.filter { !$0.isOutdated() }
                .max { $0.displayUsedPercent < $1.displayUsedPercent }
            let errorText = entry?.error.map { ErrorText.text($0, providerID: id) }
            var row: CGFloat = headline == nil ? ((errorText?.count ?? 0) > 55 ? 67 : 49) : 84
            if entry?.error != nil && usage != nil { row += 32 }
            if isExpanded(id) {
                if let usage {
                    row += CGFloat(usage.windows.count - (headline == nil ? 0 : 1)) * 53 + 16
                }
                if controller.cost(id, days: 1) != nil && controller.cost(id, days: 7) != nil {
                    row += 38
                }
            }
            return height + row + 1
        }
    }

    /// A saved choice wins. Until a provider is clicked, only the fullest current lane starts expanded.
    private var defaultExpandedProvider: String? {
        var fullest: (id: String, used: Double)?
        let now = Date()
        for id in providerIDs {
            guard let usage = controller.entry(id)?.usage,
                  let used = usage.windows.filter({ !$0.isOutdated(now: now) }).map(\.displayUsedPercent).max()
            else { continue }
            if fullest == nil || used > fullest!.used { fullest = (id, used) }
        }
        return fullest?.id
    }

    private func isExpanded(_ id: String) -> Bool {
        expandedProviders[id] ?? (id == defaultExpandedProvider)
    }

    private func toggle(_ id: String) {
        expandedProviders[id] = !isExpanded(id)
        UserDefaults.standard.set(expandedProviders, forKey: "menu.expandedProviders")
    }

    private func name(_ id: String) -> String {
        switch id {
        case "claude": "Claude Code"
        case "codex": "OpenAI Codex"
        default: MacSourceConfiguration.displayName(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
            HStack {
                BrandWordmark(font: .headline)
                Spacer()
                if controller.isPublishing { ProgressView().controlSize(.small) }
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(providerIDs.enumerated()), id: \.element) { index, id in
                        if index > 0 { Divider() }
                        ProviderSection(providerID: id, name: name(id), controller: controller,
                                        expanded: isExpanded(id), onToggle: { toggle(id) })
                            .padding(.vertical, SoftTheme.Space.sm)
                    }
                }
            }
            .frame(height: min(providerContentHeight, 500))
            Divider()
            PublishFooter(controller: controller)
            if controller.legacyJobLoaded {
                Label("The old usage-relay job is still running. See Settings.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Publish now") { Task { await controller.publishNow() } }
                    .disabled(controller.isPublishing)
                Spacer()
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(SoftTheme.Space.lg)
        .frame(width: 340)
    }
}

private struct ProviderSection: View {
    let providerID: String
    let name: String
    let controller: RelayController
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        let entry = controller.entry(providerID)
        let headline = entry?.usage.flatMap(headline)
        VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                    HStack(spacing: SoftTheme.Space.sm) {
                        SoftIconBadge(SoftTheme.providerSymbol(providerID), tint: SoftTheme.providerTint(providerID), size: 22)
                        Text(name).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        if let source = entry?.source { SourceBadge(source: source) }
                    }
                    if let headline {
                        HStack(spacing: SoftTheme.Space.xs) {
                            Text(headline.kind.title).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            Text(UsageFormatter.percentText(headline.displayUsedPercent)).monospacedDigit()
                        }
                        .font(.caption)
                        UsageBar(window: headline, mode: .used)
                            .frame(height: 6)
                        if let note = note(for: headline) {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    } else if entry?.usage != nil {
                        Text("Outdated").font(.caption).foregroundStyle(.secondary)
                    } else if let error = entry?.error {
                        Text(ErrorText.text(error, providerID: providerID))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No data yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))

            if let error = entry?.error, entry?.usage != nil {
                Text(ErrorText.text(error, providerID: providerID))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if expanded {
                if let usage = entry?.usage {
                    ForEach(usage.windows.filter { $0.kind != headline?.kind }, id: \.kind) { window in
                        WindowRow(window: window)
                            .padding(.top, SoftTheme.Space.xs)
                    }
                    Text(String(format: String(localized: "Updated %@"), relative(usage.lastUpdated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                CostLine(providerID: providerID, controller: controller)
                    .padding(.top, SoftTheme.Space.xs)
            }
        }
    }

    private func headline(_ usage: UsageInfo) -> UsageWindow? {
        let now = Date()
        return usage.windows.filter { !$0.isOutdated(now: now) }
            .max { $0.displayUsedPercent < $1.displayUsedPercent }
    }

    private func note(for window: UsageWindow) -> String? {
        let now = Date()
        if let pace = UsagePace(window: window, now: now),
           pace.status == .fast || pace.status == .depleted {
            return UsageFormatter.paceText(pace, now: now, compact: true)
        }
        return UsageFormatter.resetText(for: window.resetsAt, now: now)
    }
}

private struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.kind.title).font(.caption)
                Spacer()
                if window.isOutdated() {
                    Text("Outdated").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(UsageFormatter.percentText(window.displayUsedPercent)).font(.caption.monospacedDigit())
                }
            }
            let pace = UsagePace(window: window)
            // The pace marker is taller than the bar, so the bar gets fixed room above and below it.
            UsageBar(window: window, mode: .used, pace: pace)
                .frame(height: 8)
                .padding(.vertical, 5)
                .opacity(window.isOutdated() ? 0.35 : 1)
            // Fast pace says when it runs out; otherwise the reset time, which is what matters at a glance.
            if let pace, pace.status == .fast || pace.status == .depleted {
                PaceLine(pace: pace, compact: true)
            } else if let reset = UsageFormatter.resetText(for: window.resetsAt) {
                Text(reset).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SourceBadge: View {
    let source: RelaySource

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .help(help)
    }

    private var title: LocalizedStringKey {
        switch source {
        case .statusline: "Statusline"
        case .logs: "Logs"
        case .endpoint: ""
        }
    }

    private var help: LocalizedStringKey {
        switch source {
        case .statusline: "From Claude Code's own statusline data."
        case .logs: "From the CLI's local session logs."
        case .endpoint: ""
        }
    }
}

private struct CostLine: View {
    let providerID: String
    let controller: RelayController

    var body: some View {
        if let today = controller.cost(providerID, days: 1), let week = controller.cost(providerID, days: 7) {
            HStack(spacing: SoftTheme.Space.lg) {
                CostCell(title: "Today", amount: today.usd)
                CostCell(title: "7 days", amount: week.usd)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CostCell: View {
    let title: LocalizedStringKey
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(UsageFormatter.usdText(amount)).font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

private struct PublishFooter: View {
    let controller: RelayController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = controller.lastPublish {
                Text(String(format: String(localized: "Last publish %@ (%@)"),
                            last.formatted(date: .omitted, time: .shortened), relative(last)))
                    .font(.caption)
            } else {
                Text("Not published yet").font(.caption)
            }
            if controller.envelope?.costs.isEmpty == false {
                // Said once for both providers' costs above.
                Text("API-equivalent estimate, not what your plan bills.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = controller.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if controller.isRedirected {
                Text(String(format: String(localized: "Debug output: %@"), controller.output.path))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

enum ErrorText {
    static func text(_ error: RelayErrorCode, providerID: String) -> String {
        if let message = MacSourceConfiguration.errorText(error, providerID: providerID) { return message }
        return switch (error, providerID) {
        case (.relayUnavailable, "claude"):
            String(localized: "No statusline data yet. Install the statusline wrapper in Settings, then use Claude Code (Pro/Max).")
        case (.relayUnavailable, _):
            String(localized: "No rate-limit events in the Codex logs yet. Use Codex once.")
        case (.unauthenticated, _), (.rateLimited, _):
            String(localized: "The data could not be read.")
        case (.decoding, _):
            String(localized: "The data could not be read.")
        case (.network, _), (.server, _):
            String(localized: "The data could not be read.")
        }
    }
}

func relative(_ date: Date, now: Date = Date()) -> String {
    if now.timeIntervalSince(date) < 60 { return String(localized: "just now") }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: now)
}
