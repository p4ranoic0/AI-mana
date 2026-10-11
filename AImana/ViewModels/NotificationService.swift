import AImanaCore
import UserNotifications

/// The app's entry points to notification delivery. Planning, dedupe and delivery live in `NotificationDelivery`,
/// which the widget uses too after it fetches on its own; a lock shared with the widget keeps the two from
/// announcing the same crossing.
@MainActor
enum NotificationService {
    private static var center: UNUserNotificationCenter { .current() }
    /// In public builds, sign-in expiry means AImana for Mac lost access to its sources.
    private static let delivery = NotificationDelivery(macRelayProviderIDs: ["claude", "codex"])

    /// Call after every refresh, foreground or background.
    static func didRefresh(_ states: [ProviderState]) async {
        await delivery.didRefresh(states)
    }

    /// Settings changed: re-derive the scheduled reset announcements and the daily summary from saved data.
    static func preferencesChanged() async {
        await delivery.preferencesChanged()
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks only when the user turns notifications on. Returns the resulting status.
    static func requestAuthorization() async -> UNAuthorizationStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationStatus()
    }
}

/// Shows alerts as banners even while the app is open; tapping one just opens the app.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
