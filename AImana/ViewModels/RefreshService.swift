import AImanaCore
import BackgroundTasks
import WidgetKit

/// Background refresh. iOS decides when (and whether) the task runs, and in practice it runs rarely. Every run here
/// (and every launch and foreground) copies the latest relay data into the App Group and reloads the widgets.
/// The dashboard and widget always
/// show `lastUpdated` so stale data is visible rather than silently trusted. Each run also evaluates notifications,
/// which is why alerts can arrive late: they are only as timely as the refresh that notices the change.
enum RefreshService {
    static let taskIdentifier = "\(AppGroup.keychainService).refresh"

    /// Must be called before the app finishes launching.
    static func register(service: UsageService) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, service: service)
        }
    }

    /// Queues the next run one chosen interval from now. Submitting again replaces the pending request.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: RefreshPreferences.interval().seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `BGAppRefreshTask` is not `Sendable`; BackgroundTasks documents it as safe to complete from any queue.
    private struct TaskBox: @unchecked Sendable { let task: BGAppRefreshTask }

    private static func handle(_ task: BGAppRefreshTask, service: UsageService) {
        schedule() // always queue the next attempt first
        let box = TaskBox(task: task)
        let work = Task {
            let states = await service.refresh()
            await LiveActivityService.shared.update(with: states)
            WatchSync.shared.send(states)
            WidgetStatusPreferences.update(from: states)
            await NotificationService.didRefresh(states)
            reloadWidgets()
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
