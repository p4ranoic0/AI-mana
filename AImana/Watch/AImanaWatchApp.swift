import AImanaCore
import SwiftUI

@main
struct AImanaWatchApp: App {
    init() {
        WatchConnector.shared.activate()
#if DEBUG
        WatchConnector.shared.loadSampleIfRequested()
#endif
    }

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(state: WatchState.shared)
        }
        // A payload or complication transfer from the iPhone woke the app in the background.
        .backgroundTask(.watchConnectivity) {
            await WatchConnector.shared.waitForPendingContent()
        }
    }
}
