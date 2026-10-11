import AImanaCore
import Foundation
import RelayKit

/// The shipped Mac app reads supported local data sources only.
enum MacSourceConfiguration {
    static let defaultsKeys: [String: String] = [:]
    static let optionalProviders: [String] = []
    static func options(output: URL, enabled: [String: Bool], refreshOptional: Bool) -> RelayOptions {
        RelayOptions(output: output, refreshOptionalProviders: refreshOptional)
    }
    static func endpoints(paths: RelayPaths) -> RelayPublisher.EndpointFactory { { _, _ in nil } }
    static func debounceInterval(enabled: [String: Bool]) -> TimeInterval { PublishDebounce.minInterval }
    static func displayName(_ id: String) -> String { id }
    static func errorText(_ error: RelayErrorCode, providerID: String) -> String? { nil }
    static func alertRows(optionalProviders: [String]) -> [(id: String, name: String, lanes: [AlertLane])] { [] }
}
