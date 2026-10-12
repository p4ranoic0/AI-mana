import Foundation

/// The scheduled process does not inherit environment overrides from the shell that ran setup.
public struct RelayTaskConfiguration: Codable, Sendable {
    public let home: URL
    public let stateDirectory: URL
    public let caches: URL
    public let supportDirectory: URL
    public let claudeStatuslineFile: URL
    public let environment: [String: String]

    public init(paths: RelayPaths) {
        home = paths.home
        stateDirectory = paths.stateDirectory
        caches = paths.caches
        supportDirectory = paths.supportDirectory
        claudeStatuslineFile = paths.claudeStatuslineFile
        let pathKeys = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "LOCALAPPDATA", "USERPROFILE", "OneDrive"]
        environment = paths.environment.filter { pathKeys.contains($0.key) }
    }

    public func relayPaths() -> RelayPaths {
        var paths = RelayPaths(home: home, stateDirectory: stateDirectory, caches: caches,
                               supportDirectory: supportDirectory, environment: environment, platform: .windows)
        paths.claudeStatuslineFile = claudeStatuslineFile
        return paths
    }
}
