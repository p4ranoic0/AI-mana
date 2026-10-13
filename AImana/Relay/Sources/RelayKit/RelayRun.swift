import Foundation

/// The foreground CLI and the windowless Windows task use the same publish pass.
public enum RelayRun {
    /// Resolve a foreground run or a scheduler run from its setup record.
    public static func resolve(arguments: [String], defaultPaths: RelayPaths) throws -> (RelayPaths, RelayOptions) {
        var output: URL?
        var configuration: URL?
        var includeCosts = true
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--no-costs" {
                includeCosts = false
                index += 1
                continue
            }
            guard ["--output", "--out", "--config", "--state-dir", "--cache-dir"].contains(flag),
                  arguments.indices.contains(index + 1), !arguments[index + 1].isEmpty else {
                throw SetupError.invalidArguments
            }
            let value = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
            if flag == "--config" { configuration = value }
            if flag == "--output" || flag == "--out" { output = value }
            index += 2
        }
        guard configuration == nil || output == nil else { throw SetupError.invalidArguments }
        if let configuration {
            let record = try JSONDecoder().decode(SetupRecord.self, from: Data(contentsOf: configuration))
            guard let taskConfiguration = record.taskConfiguration else {
                throw SetupError.schedulerFailed("setup.json has no task configuration")
            }
            return (taskConfiguration.relayPaths(), RelayOptions(output: record.output, includeCosts: includeCosts))
        }
        return (defaultPaths, RelayOptions(output: output ?? defaultPaths.defaultOutput, includeCosts: includeCosts))
    }

    @discardableResult
    public static func publish(paths: RelayPaths, options: RelayOptions) async throws -> PublishReport {
        try await RelayPublisher(paths: paths).publish(options)
    }
}
