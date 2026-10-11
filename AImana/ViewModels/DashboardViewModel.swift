import AImanaCore
import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var states: [ProviderState] = []
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false
    private(set) var successfulRefreshCount = 0
    private(set) var warningTransitionCount = 0
    private let service: UsageService

    init(service: UsageService) {
        self.service = service
    }

    /// Show the last persisted snapshot immediately, then fetch fresh data.
    func load() async {
        states = await service.cached()
        await refresh()
        hasLoaded = true
    }

    private var lastRefreshAt: Date?

    /// Automatic refreshes (returning to the foreground) skip if the last one was under a minute ago, so switching
    /// apps back and forth does not fire network requests every time. Pull-to-refresh calls `refresh()` directly.
    func refreshIfStale(minimumInterval: TimeInterval = 60) async {
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < minimumInterval { return }
        await refresh()
    }

    func refresh() async {
        lastRefreshAt = Date()
        isRefreshing = true
        let previous = states
        let latest = await service.refresh()
        await LiveActivityService.shared.update(with: latest)
        WatchSync.shared.send(latest)
        if SeverityTransitions.hasEscalation(previous: previous, current: latest) {
            warningTransitionCount += 1
        }
        states = latest
        WidgetStatusPreferences.update(from: latest)
        if latest.contains(where: { $0.error == nil && $0.usage != nil }) {
            successfulRefreshCount += 1
        }
        isRefreshing = false
        RefreshService.reloadWidgets()
    }
}
