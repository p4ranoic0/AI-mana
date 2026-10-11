import SwiftUI
import WidgetKit

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        ProviderWidget()
        OverviewWidget()
        UsageLiveActivityWidget()
        if #available(iOS 18.0, *) {
            UsageControl()
        }
    }
}
