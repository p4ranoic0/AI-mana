import AImanaCore
import Foundation
import WatchConnectivity

/// Keeps the Apple Watch app and its complications current. The watch has no network or credentials: after every
/// refresh the iPhone sends a compact `WatchPayload` (lanes, resets and reading times only) through
/// WatchConnectivity.
///
/// - `updateApplicationContext` always: the system keeps only the latest one and delivers it when the watch wakes.
/// - `transferCurrentComplicationUserInfo` only when the numbers moved meaningfully (see
///   `WatchPayload.isMeaningfulChange`): it wakes the watch's complications right away but has a small daily budget.
/// - When the watch app opens it asks for the latest saved reading, answered from the App Group snapshot without
///   touching the network.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    private let lock = NSLock()
    /// Sent once the session finishes activating (a refresh can land before that, e.g. in a background launch).
    private var pending: WatchPayload?
    private var lastComplicationPayload: WatchPayload?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Call at launch so the watch's requests can be answered and pending sends go out.
    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Hook for every refresh path (dashboard, background task).
    func send(_ states: [ProviderState]) {
        guard !states.isEmpty else { return }
        send(WatchPayload(states: states, mode: DisplayPreferences.mode()))
    }

    private func send(_ payload: WatchPayload) {
        guard let session else { return }
        guard session.activationState == .activated else {
            lock.withLock { pending = payload }
            activate()
            return
        }
        guard session.isPaired, session.isWatchAppInstalled, let message = try? payload.message() else { return }
        try? session.updateApplicationContext(message)

        let previous = lock.withLock { lastComplicationPayload }
        if session.isComplicationEnabled,
           payload.isMeaningfulChange(from: previous, remainingTransfers: session.remainingComplicationUserInfoTransfers) {
            session.transferCurrentComplicationUserInfo(message)
            lock.withLock { lastComplicationPayload = payload }
        }
    }

    /// Display mode changed on the phone: resend the saved reading so the watch headlines the same number, without
    /// another network refresh.
    func resendSaved() {
        send(savedPayload())
    }

    private func savedPayload() -> WatchPayload {
        WatchPayload(snapshot: AppGroup.snapshotStore().load(), mode: DisplayPreferences.mode())
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        let payload = lock.withLock { () -> WatchPayload? in defer { pending = nil }; return pending }
        if let payload { send(payload) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchPayload.requestKey] != nil, let reply = try? savedPayload().message() else {
            replyHandler([:])
            return
        }
        replyHandler(reply)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again so the new one gets updates.
    func sessionDidDeactivate(_ session: WCSession) {
        lock.withLock { lastComplicationPayload = nil }
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // Watch app just installed or complication added: give it something to show.
        let saved = savedPayload()
        if session.activationState == .activated, session.isWatchAppInstalled, !saved.providers.isEmpty {
            send(saved)
        }
    }
}
