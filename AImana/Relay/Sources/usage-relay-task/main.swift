import Foundation
import RelayKit

/// Scheduled by usage-relay setup. The GUI subsystem avoids creating a console window.
@main
struct RelayTaskMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-check"] { return }
        guard args.count == 2, !args[1].isEmpty else {
            log("Invalid task arguments")
            exit(2)
        }
        let paths: RelayPaths
        let output: URL
        let logDirectory: URL
        if args[0] == "--config" {
            let file = URL(fileURLWithPath: args[1])
            logDirectory = file.deletingLastPathComponent()
            do {
                let record = try JSONDecoder().decode(SetupRecord.self, from: Data(contentsOf: file))
                guard let configuration = record.taskConfiguration else {
                    throw SetupError.schedulerFailed("setup.json has no task configuration")
                }
                paths = configuration.relayPaths()
                output = record.output
            } catch {
                log("Cannot read task configuration: \(error)", in: logDirectory)
                exit(2)
            }
        } else if args[0] == "--output" {
            // Existing tasks created by older releases still use this form until setup is run again.
            paths = .standard
            output = URL(fileURLWithPath: args[1])
            logDirectory = paths.supportDirectory
        } else {
            log("Invalid task arguments")
            exit(2)
        }
        do {
            _ = try await RelayRun.publish(paths: paths, options: RelayOptions(output: output))
        } catch {
            log("Publish failed: \(error)", in: logDirectory)
            exit(1)
        }
    }

    private static func log(_ message: String, in directory: URL = RelayPaths.standard.supportDirectory) {
        let file = directory.appendingPathComponent("relay-task.log")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = (try? Data(contentsOf: file)) ?? Data()
            if data.count > 64 * 1024 { data = Data(data.suffix(64 * 1024)) }
            data.append(Data("\(Date()): \(message)\n".utf8))
            try data.write(to: file, options: .atomic)
        } catch {}
    }
}
