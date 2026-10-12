import Foundation

/// The foreground CLI and the windowless Windows task use the same publish pass.
public enum RelayRun {
    @discardableResult
    public static func publish(paths: RelayPaths, options: RelayOptions) async throws -> PublishReport {
        try await RelayPublisher(paths: paths).publish(options)
    }
}
