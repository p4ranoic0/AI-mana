import AImanaCore
import AppKit
import RelayKit
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: RelayController
    @State private var showRemovalCommand = false

    var body: some View {
        Form {
            Section("Publishing") {
                Picker("Refresh every", selection: $controller.refreshMinutes) {
                    ForEach(MacSettings.refreshChoices, id: \.self) { minutes in
                        Text(String(format: String(localized: "%lld min"), minutes)).tag(minutes)
                    }
                }
                LabeledContent("Publish location") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(controller.output.path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                        if controller.isRedirected {
                            Text("Debug output (launch argument): iCloud Drive is not touched.").font(.caption).foregroundStyle(.orange)
                        } else if controller.iCloudDriveAvailable {
                            Text("iCloud Drive is available.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("iCloud Drive was not found. Turn it on in System Settings › Apple Account › iCloud.")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Toggle("Open at login", isOn: Binding(get: { controller.launchAtLoginEnabled },
                                                      set: { controller.setLaunchAtLogin($0) }))
            }

            NotificationSettingsSection(notifier: controller.notifier,
                                        optionalProviders: controller.enabledOptionalProviders)

            Section("Claude Code statusline") {
                LabeledContent("Status") { Text(statuslineStatusText) }
                if let capture = controller.lastStatuslineCapture {
                    LabeledContent("Last data from Claude Code") { Text(relative(capture)) }
                }
                Text("AImana reads Claude Code's official statusline data (5-hour and weekly limits, Pro/Max only). Install adds a small wrapper to ~/.claude/settings.json that saves those numbers and still runs your current statusline. A backup is kept and Uninstall restores the previous setting exactly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    switch controller.statuslineStatus {
                    case .notInstalled:
                        Button("Install") { controller.installStatusline() }
                    case .installed:
                        Button("Uninstall") { controller.uninstallStatusline() }
                    case .replacedElsewhere:
                        Button("Install again") { controller.installStatusline() }
                        Button("Forget") { controller.forgetStatusline() }
                    }
                    Button("Check again") { controller.refreshStatus() }
                }
                if let message = controller.statuslineMessage {
                    Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }

            SourceSettingsSection(controller: controller)

            if controller.legacyJobLoaded || controller.legacyJobInstalled {
                Section("Old relay job") {
                    Text("The previous usage-relay LaunchAgent from before this app is still installed. It writes the same file, so the two can overwrite each other. AImana does not remove it for you.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(showRemovalCommand ? "Hide removal command" : "Show removal command") {
                        showRemovalCommand.toggle()
                    }
                    if showRemovalCommand {
                        Text(LegacyRelayJob.removalCommand())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(SoftTheme.Space.sm)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Text("Run it in Terminal yourself.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onAppear { controller.refreshStatus() }
    }

    private var statuslineStatusText: LocalizedStringKey {
        switch controller.statuslineStatus {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .replacedElsewhere: "Changed outside AImana"
        }
    }
}

/// Alerts sent by this Mac right after each publish. Same alert types as the iPhone, configured separately.
private struct NotificationSettingsSection: View {
    let notifier: MacNotifier
    let optionalProviders: [String]

    var body: some View {
        let prefs = notifier.preferences
        Section("Notifications") {
            Toggle("Alerts from this Mac", isOn: Binding(get: { prefs.isEnabled },
                                                       set: { on in Task { await notifier.setEnabled(on) } }))
            if notifier.authorization == .denied {
                HStack {
                    Text("Notifications are turned off for AImana in System Settings.")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") { MacNotifier.openSystemSettings() }.controlSize(.small)
                }
            }
            if prefs.isEnabled {
                ForEach(MacNotifier.alertRows(optionalProviders: optionalProviders), id: \.id) { provider in
                    ForEach(provider.lanes) { lane in
                        LabeledContent {
                            ThresholdMenu(notifier: notifier, providerID: provider.id, lane: lane)
                        } label: {
                            Text(verbatim: "\(provider.name) · \(lane.title)")
                        }
                    }
                }
                SourceSettingsNote(optionalProviders: optionalProviders)
                Toggle("Fast pace", isOn: binding(\.paceAlerts))
                Toggle("Quota available again", isOn: binding(\.recoveryAlerts))
                Toggle("Lost access", isOn: binding(\.loginAlerts))
                Toggle("Daily summary", isOn: binding(\.dailySummary))
                if prefs.dailySummary {
                    DatePicker("Summary time", selection: summaryTime, displayedComponents: .hourAndMinute)
                }
            }
            Text("These alerts come from this Mac and arrive right away while it is awake: AImana publishes soon after Claude Code's statusline changes (at most every 30 seconds) and on its regular schedule otherwise. The iPhone has its own alert settings and remembers separately what it already announced, so with both on you may get the same alert on both devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await notifier.refreshAuthorization() }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { notifier.preferences[keyPath: keyPath] },
                set: { value in notifier.update { $0[keyPath: keyPath] = value } })
    }

    private var summaryTime: Binding<Date> {
        Binding(get: {
            let minutes = notifier.preferences.summaryMinutes
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            notifier.update { $0.summaryMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
        })
    }
}

/// Multi-select of alert levels for one provider lane. No level selected means the lane stays quiet.
private struct ThresholdMenu: View {
    let notifier: MacNotifier
    let providerID: String
    let lane: AlertLane

    var body: some View {
        let selected = notifier.thresholds(providerID, lane)
        let choices = Array(Set(MacNotifier.thresholdChoices + selected)).sorted()
        Menu {
            ForEach(choices, id: \.self) { value in
                Toggle(isOn: Binding(get: { selected.contains(value) },
                                     set: { _ in notifier.toggleThreshold(value, providerID: providerID, lane: lane) })) {
                    Text(verbatim: UsageFormatter.percentText(Double(value)))
                }
            }
        } label: {
            if selected.isEmpty {
                Text("Off")
            } else {
                Text(verbatim: selected.map { UsageFormatter.percentText(Double($0)) }.joined(separator: ", "))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
