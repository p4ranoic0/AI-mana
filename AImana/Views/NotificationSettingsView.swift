import AImanaCore
import SwiftUI
import UserNotifications

/// Which alerts to send. Everything is stored in the App Group; the planner in AImanaCore decides what fires.
struct NotificationSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var prefs = NotificationStore.preferences()
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    private static let providers = [(id: "claude", name: "Claude Code"), (id: "codex", name: "OpenAI Codex")]
    private typealias Prefs = NotificationPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Notifications", isOn: masterBinding)
                if prefs.isEnabled && authorization == .denied {
                    Text("Notifications are turned off for AImana in iOS Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text("iOS decides how often AImana can refresh in the background, so alerts may arrive late. Opening the app checks right away.")
            }
            .listRowBackground(SoftTheme.peach.opacity(scheme == .dark ? 0.13 : 0.20))

            if prefs.isEnabled {
                ForEach(Self.providers, id: \.id) { provider in
                    Section {
                        ForEach(AlertLane.allCases) { lane in laneRows(providerID: provider.id, lane: lane) }
                    } header: {
                        Text(verbatim: provider.name)
                    } footer: {
                        Text("Thresholds always count used quota, whatever display mode you choose.")
                    }
                    .listRowBackground(SoftTheme.blue.opacity(scheme == .dark ? 0.12 : 0.20))
                }

                Section {
                    Toggle("Fast pace", isOn: $prefs.paceAlerts)
                    Toggle("Quota available again", isOn: $prefs.recoveryAlerts)
                    Toggle("Sign-in expired", isOn: $prefs.loginAlerts)
                } header: {
                    Text("Other alerts")
                } footer: {
                    Text("Fast pace alerts once per window when the projection says the quota runs out before it resets. Quota available again follows windows that ran out or passed your highest threshold. Sign-in alerts cover AImana for Mac's access to Claude Code and Codex.")
                }
                .listRowBackground(SoftTheme.pink.opacity(scheme == .dark ? 0.12 : 0.17))

                Section {
                    Toggle("Daily summary", isOn: $prefs.dailySummary)
                    if prefs.dailySummary {
                        DatePicker("Time", selection: summaryTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Sends the latest usage AImana knows at that time. The numbers come from the last refresh.")
                }
                .listRowBackground(SoftTheme.yellow.opacity(scheme == .dark ? 0.10 : 0.18))
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftTheme.canvas(scheme))
        .fontDesign(.rounded)
        .softText(.body)
        .hardTopScrollEdge()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { authorization = await NotificationService.authorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            // The user may have changed the permission in iOS Settings meanwhile.
            if phase == .active { Task { authorization = await NotificationService.authorizationStatus() } }
        }
        .onChange(of: prefs) { _, value in
            NotificationStore.setPreferences(value)
            Task { await NotificationService.preferencesChanged() }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func laneRows(providerID: String, lane: AlertLane) -> some View {
        let settings = prefs.window(providerID: providerID, lane: lane)
        Toggle(lane.title, isOn: Binding(
            get: { settings.isEnabled },
            set: { isOn in mutate(providerID, lane) { $0.isEnabled = isOn } }))
        if settings.isEnabled {
            ForEach(Array(settings.thresholds.enumerated()), id: \.element) { index, value in
                Stepper(value: thresholdBinding(providerID, lane, index: index),
                        in: Prefs.thresholdRange, step: Prefs.thresholdStep) {
                    Text("Alert at \(UsageFormatter.percentText(Double(value))) used")
                        .monospacedDigit()
                }
                .padding(.leading, SoftTheme.Space.md)
            }
            .onDelete { offsets in
                mutate(providerID, lane) { $0.thresholds.remove(atOffsets: offsets) }
            }
            if settings.thresholds.count < Prefs.maxThresholds {
                Button("Add threshold") {
                    mutate(providerID, lane) { settings in
                        if let free = Self.freeThreshold(near: settings.thresholds) { settings.thresholds.append(free) }
                    }
                }
                .padding(.leading, SoftTheme.Space.md)
            }
        }
    }

    // MARK: - Bindings

    private var masterBinding: Binding<Bool> {
        Binding(get: { prefs.isEnabled }, set: { isOn in
            prefs.isEnabled = isOn
            // Permission is requested only when the user opts in, never at launch.
            if isOn { Task { authorization = await NotificationService.requestAuthorization() } }
        })
    }

    private var summaryTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: prefs.summaryMinutes / 60, minute: prefs.summaryMinutes % 60,
                                  second: 0, of: .now) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            prefs.summaryMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    /// Steps skip values the lane already has, so two rows never merge into one.
    private func thresholdBinding(_ providerID: String, _ lane: AlertLane, index: Int) -> Binding<Int> {
        Binding(get: {
            let values = prefs.window(providerID: providerID, lane: lane).thresholds
            return values.indices.contains(index) ? values[index] : Prefs.thresholdRange.lowerBound
        }, set: { proposed in
            mutate(providerID, lane) { settings in
                guard settings.thresholds.indices.contains(index) else { return }
                let old = settings.thresholds[index]
                let direction = proposed >= old ? Prefs.thresholdStep : -Prefs.thresholdStep
                var value = proposed
                while settings.thresholds.contains(value) && value != old { value += direction }
                guard Prefs.thresholdRange.contains(value) else { return }
                settings.thresholds[index] = value
            }
        })
    }

    /// Edits one lane; `setWindow` re-normalizes the thresholds (sorted, unique, in range).
    private func mutate(_ providerID: String, _ lane: AlertLane, _ change: (inout WindowAlertSettings) -> Void) {
        var settings = prefs.window(providerID: providerID, lane: lane)
        change(&settings)
        prefs.setWindow(settings, providerID: providerID, lane: lane)
    }

    /// A free 5 % step below the lowest threshold, else above the highest.
    static func freeThreshold(near values: [Int]) -> Int? {
        let start = (values.min() ?? 90) - 10
        let below = stride(from: start, through: Prefs.thresholdRange.lowerBound, by: -Prefs.thresholdStep)
        let above = stride(from: start + Prefs.thresholdStep, through: Prefs.thresholdRange.upperBound,
                           by: Prefs.thresholdStep)
        return (Array(below) + Array(above)).first { Prefs.thresholdRange.contains($0) && !values.contains($0) }
    }
}
