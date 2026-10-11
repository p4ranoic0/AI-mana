import AImanaCore
import Foundation
import WidgetKit

/// The widget extension's side of the shared intents: refreshes its available data, then reloads every widget and control.
enum IntentRefreshRunner {
    static func refresh(providerIDs: [String], maxAge: TimeInterval, deadline: TimeInterval) async {
        await WidgetRefresher.refreshOnDemand(maxAge: maxAge, deadline: deadline)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }
}
