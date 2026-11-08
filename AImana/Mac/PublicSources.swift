import AImanaCore
import Foundation
import RelayKit
#if SWIFT_PACKAGE
import RelayDirect
#endif

/// The shipped Mac app: local sources, plus Claude and Codex directly once the user turns them on and accepts the
/// notice.
enum MacSourceConfiguration {
    static let defaultsKeys = ["claude": "claudeEndpoint", "codex": "codexEndpoint"]
    static let optionalProviders: [String] = []
    static func options(output: URL, enabled: [String: Bool], refreshOptional: Bool) -> RelayOptions {
        MacDirectOptions.make(output: output, enabled: enabled, consent: DirectSourcesSection.consent,
                              refreshOptional: refreshOptional)
    }
    static func endpoints(paths: RelayPaths) -> RelayPublisher.EndpointFactory {
        DirectEndpoints.factory(paths: paths, log: { NSLog("[AImana] %@", $0) },
                                isAllowed: DirectSourcesSection.isAllowed)
    }
    static func debounceInterval(enabled: [String: Bool]) -> TimeInterval {
        MacDirectOptions.debounce(enabled: enabled, consent: DirectSourcesSection.consent)
    }
    static func displayName(_ id: String) -> String { id }
    static func errorText(_ error: RelayErrorCode, providerID: String) -> String? { nil }
    static func alertRows(optionalProviders: [String]) -> [(id: String, name: String, lanes: [AlertLane])] { [] }
}
