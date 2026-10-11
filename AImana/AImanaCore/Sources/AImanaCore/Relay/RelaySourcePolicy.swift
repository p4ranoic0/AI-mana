import Foundation

/// Decides which source the Mac publishes for one provider.
///
/// - Opt-in endpoint on and it succeeded → endpoint data (`source: .endpoint`).
/// - Otherwise → the local source (Claude statusline file, Codex session logs).
/// - Both failed → the endpoint's error when the user opted in (it explains more, e.g. "sign in on the Mac"),
///   else the local one.
///
/// Costs and history are not part of this choice: they come from local logs and the relay's own recording, and
/// are attached to the envelope whatever source wins.
public enum RelaySourcePolicy {
    public static func entry(providerID: String,
                             endpoint: Result<UsageInfo, UsageProviderError>?,
                             local: Result<UsageInfo, UsageProviderError>,
                             localSource: RelaySource) -> RelayEntry {
        if case .success(let usage) = endpoint {
            return RelayEntry(providerID: providerID, usage: usage, error: nil, source: .endpoint)
        }
        switch local {
        case .success(let usage):
            return RelayEntry(providerID: providerID, usage: usage, error: nil, source: localSource)
        case .failure(let localError):
            if case .failure(let endpointError) = endpoint {
                return RelayEntry(providerID: providerID, usage: nil, error: RelayErrorCode(endpointError), source: .endpoint)
            }
            return RelayEntry(providerID: providerID, usage: nil, error: RelayErrorCode(localError), source: localSource)
        }
    }
}
