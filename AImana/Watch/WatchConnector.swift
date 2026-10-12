import AImanaCore
import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// What the watch screen shows: the last payload saved from the iPhone.
@MainActor
@Observable
final class WatchState {
    static let shared = WatchState()
    nonisolated static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private(set) var payload: WatchPayload?
    /// Set while asking the iPhone; `requestFailed` when it could not be reached.
    private(set) var isRequesting = false
    private(set) var requestFailed = false

    private init() {
        payload = Self.isDemo ? DemoProviders.watchPayload() : WatchPayloadStore.shared().load()
    }

    func reload() {
        guard !Self.isDemo else { return }
        payload = WatchPayloadStore.shared().load()
    }

    func requestFromPhone() {
        guard !Self.isDemo else { return }
        guard !isRequesting else { return }
        isRequesting = true
        requestFailed = false
        WatchConnector.shared.requestLatest { [weak self] received in
            Task { @MainActor in
                self?.isRequesting = false
                self?.requestFailed = !received
                self?.reload()
            }
        }
    }
}

/// Receives payloads from the iPhone, saves them for the app and the complications, and reloads the complications.
/// Never touches the network.
final class WatchConnector: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnector()
    private let store = WatchPayloadStore.shared()

    func activate() {
        guard !WatchState.isDemo else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Asks the iPhone (which answers from its saved snapshot) for the latest reading.
    func requestLatest(_ completion: @escaping @Sendable (Bool) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return completion(false) }
        session.sendMessage([WatchPayload.requestKey: true], replyHandler: { [weak self] reply in
            completion(self?.receive(reply) ?? false)
        }, errorHandler: { _ in completion(false) })
    }

    /// Lets a WatchConnectivity background wake finish delivering before the system suspends the app.
    func waitForPendingContent() async {
        guard !WatchState.isDemo else { return }
        activate()
        for _ in 0..<20 where WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    @discardableResult
    func receive(_ message: [String: Any]) -> Bool {
        guard !WatchState.isDemo else { return false }
        guard let payload = WatchPayload.from(message: message) else { return false }
        if (try? store.save(payload)) == true {
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { @MainActor in WatchState.shared.reload() }
        return true
    }

#if DEBUG
    /// Simulator only: stands in for the iPhone (`-AImanaWatchSample fresh|stale|signin`).
    func loadSampleIfRequested() {
        guard let variant = WatchSample.requested else { return }
        store.clear()   // the sample may be older than what is saved
        if let message = try? WatchSample.payload(variant).message() { receive(message) }
    }
#endif

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // Whatever the iPhone sent while the watch app was not running.
        if activationState == .activated { receive(session.receivedApplicationContext) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    /// Complication transfers from `transferCurrentComplicationUserInfo`.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }
}
