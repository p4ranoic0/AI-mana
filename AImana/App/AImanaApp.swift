import AImanaCore
import SwiftUI
import UserNotifications

@main
struct AImanaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let environment: AppEnvironment
    @State private var dashboard: DashboardViewModel
    /// The notification center keeps only a weak reference to its delegate.
    private let notificationDelegate = NotificationDelegate()

    init() {
        let environment = AppEnvironment.shared
        self.environment = environment
        _dashboard = State(initialValue: environment.dashboard)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        RefreshService.register(service: environment.service)
        WatchSync.shared.activate()
        RefreshService.schedule()   // not only on the way to the background: a launch that never leaves still counts
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(model: dashboard)
                // Every foreground refresh lands here; the background task calls the same entry point.
                .onChange(of: dashboard.states) { _, states in
                    Task { await NotificationService.didRefresh(states) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                RefreshService.schedule()
            case .active where dashboard.hasLoaded:
                // Back in the foreground: pick up what the Mac published meanwhile; the refresh also saves the
                // App Group snapshot and reloads the widgets. The first launch is covered by the dashboard's load.
                Task { await dashboard.refreshIfStale() }
            default:
                break
            }
        }
    }
}
