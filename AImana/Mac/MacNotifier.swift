import AImanaCore
import AppKit
import Foundation
import Observation
import RelayKit
@preconcurrency import UserNotifications

/// Alerts straight from the Mac, right after each publish. It runs the same planner as the iPhone over the entries the
/// Mac just published, but keeps its own preferences and dedupe state next to the relay's state (not in the iPhone's
/// App Group), so the two devices are configured and deduplicated separately.
@MainActor @Observable
final class MacNotifier {
    /// Providers whose Mac access can expire ("Lost access" alerts): the opt-in Claude/Codex endpoints.
    static let providers: [(id: String, name: String)] = [("claude", "Claude Code"), ("codex", "OpenAI Codex")]

    static func alertRows(optionalProviders: [String]) -> [(id: String, name: String, lanes: [AlertLane])] {
        var rows = providers.map { (id: $0.id, name: $0.name, lanes: AlertLane.allCases) }
        rows.append(contentsOf: MacSourceConfiguration.alertRows(optionalProviders: optionalProviders))
        return rows
    }
    /// The levels offered in Settings; anything else saved earlier is still shown and can be removed.
    static let thresholdChoices = [50, 70, 80, 90, 95]

    private(set) var preferences: NotificationPreferences
    /// Nil until checked; the notification center is not touched while alerts are off.
    private(set) var authorization: UNAuthorizationStatus?

    private let preferencesFile: NotificationPreferencesFile
    private let delivery: NotificationDelivery
    private var presenter: ForegroundPresenter?

    /// `stateDirectory` holds the preferences and the dedupe state; `output` is the published file, read back to
    /// rebuild the daily summary when the settings change.
    init(stateDirectory: URL, output: URL) {
        let file = NotificationPreferencesFile(url: stateDirectory.appendingPathComponent("notification-preferences.json"))
        preferencesFile = file
        preferences = file.load()
        delivery = NotificationDelivery(
            lock: FileLock(url: stateDirectory.appendingPathComponent("notifications.lock"), timeout: 10),
            stateFile: NotificationStateFile(url: stateDirectory.appendingPathComponent("notification-state.json"),
                                             legacyFallback: false),
            settings: NotificationSettingsSource(
                preferences: { file.load() },
                savedUsages: { (try? RelayEnvelope.decode(Data(contentsOf: output)))?.entries.compactMap(\.usage) ?? [] }))
        if preferences.isEnabled { installPresenter() }
    }

    // MARK: Publishing

    /// Call after every successful publish. While alerts are off it only records what it saw.
    func didPublish(_ report: PublishReport) async {
        let states = report.envelope.entries.map(ProviderState.init(relayEntry:))
        let logins = report.macLogins(providerIDs: Self.providers.map(\.id))
        await delivery.didRefresh(states, logins: logins, loginOrigin: .thisMac)
    }

    // MARK: Settings

    /// Turning alerts on asks for permission first; they stay off if the user declines.
    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            update { $0.isEnabled = false }
            return
        }
        installPresenter()
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorization = await center.notificationSettings().authorizationStatus
        if granted { update { $0.isEnabled = true } }
    }

    func refreshAuthorization() async {
        guard preferences.isEnabled || authorization != nil else { return }
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func update(_ change: (inout NotificationPreferences) -> Void) {
        let previous = preferences
        var next = previous
        change(&next)
        guard next != previous else { return }
        preferences = next
        preferencesFile.save(next)
        // Re-derive scheduled reset announcements and the daily summary; turning alerts off removes them.
        if next.isEnabled || previous.isEnabled {
            Task { await delivery.preferencesChanged() }
        }
    }

    func thresholds(_ providerID: String, _ lane: AlertLane) -> [Int] {
        let settings = preferences.window(providerID: providerID, lane: lane)
        return settings.isEnabled ? settings.thresholds : []
    }

    func toggleThreshold(_ value: Int, providerID: String, lane: AlertLane) {
        var values = Set(thresholds(providerID, lane))
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
        let sorted = values.sorted()
        update {
            $0.setWindow(WindowAlertSettings(isEnabled: !sorted.isEmpty, thresholds: sorted),
                         providerID: providerID, lane: lane)
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The menu bar window makes the app active, and macOS hides an active app's banners unless asked.
    private func installPresenter() {
        guard presenter == nil else { return }
        let presenter = ForegroundPresenter()
        UNUserNotificationCenter.current().delegate = presenter
        self.presenter = presenter
    }
}

private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
