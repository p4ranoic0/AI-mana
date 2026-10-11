import AImanaCore
import Foundation
import WidgetKit

/// The app's side of the shared intents (Siri, Shortcuts, the widgets' refresh button): the same refresh as the
/// dashboard's pull-to-refresh, so the Mac relay is read too and the open dashboard shows the result.
@MainActor
enum IntentRefreshRunner {
    /// Refreshes when any of `providerIDs` is missing or older than `maxAge`; returns by `deadline` at the latest,
    /// leaving a slower fetch to finish (and save) on its own.
    static func refresh(providerIDs: [String], maxAge: TimeInterval, deadline: TimeInterval) async {
        let items = AppGroup.snapshotStore().load()
        guard UsageAnswer.needsRefresh(items: items, providerIDs: providerIDs, maxAge: maxAge) else { return }
        await IntentDeadline.run(deadline) { await refreshNow() }
    }

    private static func refreshNow() async {
        let dashboard = AppEnvironment.shared.dashboard
        await dashboard.refresh()   // saves the snapshot, updates the Live Activity, reloads the widgets
        await NotificationService.didRefresh(dashboard.states)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }
}
