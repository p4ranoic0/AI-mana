import Foundation

public protocol RelayCommandExecutor: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> Int32
}

public struct SystemRelayCommandExecutor: RelayCommandExecutor {
    public init() {}
    public func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public struct SetupOptions: Equatable, Sendable {
    public let output: URL?
    public let interval: Int

    public init(arguments: [String]) throws {
        var output: URL?
        var interval = 5
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard ["--output", "--interval"].contains(flag), arguments.indices.contains(index + 1) else {
                throw SetupError.invalidArguments
            }
            let value = arguments[index + 1]
            if flag == "--output" {
                guard !value.isEmpty else { throw SetupError.invalidArguments }
                output = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            } else {
                guard let minutes = Int(value), minutes >= 1 else { throw SetupError.invalidArguments }
                interval = minutes
            }
            index += 2
        }
        self.output = output
        self.interval = interval
    }
}

public enum SetupError: Error, Equatable {
    case invalidArguments
    case schedulerFailed(String)
}

public struct SetupRecord: Codable, Sendable {
    public let output: URL
    public let interval: Int
    public let statuslineInstalled: Bool
    public let schedulerInstalled: Bool
    public let executable: URL?
    public let taskExecutable: URL?
    public let taskName: String?
    public let taskConfiguration: RelayTaskConfiguration?
}

public struct RelaySetup: Sendable {
    public static let taskName = "AImanaUsageRelay"
    public let paths: RelayPaths
    public let executable: URL
    public let executor: any RelayCommandExecutor
    private let publish: @Sendable (RelayOptions) async throws -> Void

    public init(paths: RelayPaths = .standard,
                executable: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]),
                executor: any RelayCommandExecutor = SystemRelayCommandExecutor(),
                publish: (@Sendable (RelayOptions) async throws -> Void)? = nil) {
        self.paths = paths
        self.executable = RelayExecutable.stable(executable)
        self.executor = executor
        self.publish = publish ?? { _ = try await RelayPublisher(paths: paths).publish($0) }
    }

    public var recordFile: URL { paths.supportDirectory.appendingPathComponent("setup.json") }
    public var serviceFile: URL { paths.home.appendingPathComponent(".config/systemd/user/aimana-relay.service") }
    public var timerFile: URL { paths.home.appendingPathComponent(".config/systemd/user/aimana-relay.timer") }
    public var hiddenLauncher: URL { paths.supportDirectory.appendingPathComponent("relay-hidden.vbs") }
    public var taskExecutable: URL { executable.deletingLastPathComponent().appendingPathComponent("usage-relay-task.exe") }
    public var configuredTaskName: String { paths.environment["AIMANA_TASK_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.taskName }
    public var statusline: StatuslineInstaller { StatuslineInstaller(paths: paths, executable: executable) }

    public var hasClaude: Bool {
        paths.claudeProjectRoots.contains { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
    }
    public var hasCodex: Bool {
        paths.codexSessionRoots.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func setup(_ options: SetupOptions) async throws -> [String] {
        let output = options.output ?? paths.defaultOutput
        if paths.platform == .windows && !FileManager.default.fileExists(atPath: taskExecutable.path) {
            throw SetupError.schedulerFailed("missing usage-relay-task.exe next to usage-relay.exe")
        }
        let claude = hasClaude, codex = hasCodex
        var lines = ["Claude Code: \(claude ? "found" : "not found")", "Codex: \(codex ? "found" : "not found")"]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await publish(RelayOptions(output: output))
        lines.append("Published: \(output.path)")
        if claude {
            try statusline.install()
            lines.append("Claude statusline capture installed")
        }
        // The scheduler can start immediately; its configuration must already exist.
        try writeRecord(output: output, interval: options.interval, statuslineInstalled: claude, scheduled: false)
        var scheduled = false
        switch paths.platform {
        case .windows:
            let command = Self.windowsTaskArguments(interval: options.interval, executable: taskExecutable,
                                                    configuration: recordFile, taskName: configuredTaskName)
            guard executor.run(Self.schtasksPath(environment: paths.environment), command) == 0 else {
                throw SetupError.schedulerFailed("schtasks.exe /Create")
            }
            scheduled = true
            lines.append("Windows scheduled task installed (every \(options.interval) minutes, hidden)")
        case .linux:
            if executor.run("/usr/bin/systemctl", ["--user", "show-environment"]) == 0 {
                try FileManager.default.createDirectory(at: serviceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(Self.systemdService(executable: executable, configuration: recordFile).utf8)
                    .write(to: serviceFile, options: .atomic)
                try Data(Self.systemdTimer(interval: options.interval).utf8).write(to: timerFile, options: .atomic)
                guard executor.run("/usr/bin/systemctl", ["--user", "daemon-reload"]) == 0,
                      executor.run("/usr/bin/systemctl", ["--user", "enable", "--now", "aimana-relay.timer"]) == 0 else {
                    throw SetupError.schedulerFailed("systemctl --user enable --now")
                }
                scheduled = true
                lines.append("systemd user timer installed (every \(options.interval) minutes)")
            } else {
                lines.append("systemd user manager unavailable. Add this crontab line:")
                let cadence = options.interval <= 59 ? "*/\(options.interval) * * * *"
                    : "* * * * * [ $(( $(date +\\%s) / 60 \\% \(options.interval) )) -eq 0 ] &&"
                let command = Self.linuxRunCommand(executable: executable, configuration: recordFile,
                                                   quote: Self.shellQuote)
                lines.append("\(cadence) \(command)")
            }
        case .macOS: break
        }
        try writeRecord(output: output, interval: options.interval, statuslineInstalled: claude, scheduled: scheduled)
        lines.append("On iPhone: AI·mana › Settings › Choose relay file… Select this file in iCloud Drive or OneDrive.")
        return lines
    }

    private func writeRecord(output: URL, interval: Int, statuslineInstalled: Bool, scheduled: Bool) throws {
        let record = SetupRecord(output: output, interval: interval, statuslineInstalled: statuslineInstalled,
                                 schedulerInstalled: scheduled, executable: executable,
                                 taskExecutable: paths.platform == .windows ? taskExecutable : nil,
                                 taskName: paths.platform == .windows ? configuredTaskName : nil,
                                 taskConfiguration: paths.platform == .macOS ? nil : RelayTaskConfiguration(paths: paths))
        try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: recordFile, options: .atomic)
    }

    public func doctor() -> (lines: [String], healthy: Bool) {
        var lines = ["usage-relay \(RelayVersion.current)",
                     "Claude: \(paths.claudeProjectRoots.map(\.path).joined(separator: ", ")) (\(hasClaude ? "found" : "missing"))",
                     "Codex: \(paths.codexSessionRoots.map(\.path).joined(separator: ", ")) (\(hasCodex ? "found" : "missing"))",
                     "Support: \(paths.supportDirectory.path)", "State: \(paths.stateDirectory.path)",
                     "Cache: \(paths.caches.path)"]
        var healthy = true
        let record = loadRecord()
        if let recordedExecutable = record?.executable,
           !FileManager.default.fileExists(atPath: recordedExecutable.path) {
            healthy = false
            lines.append("Missing recorded executable: \(recordedExecutable.path). Fix: usage-relay setup")
        }
        if let taskExecutable = record?.taskExecutable,
           !FileManager.default.fileExists(atPath: taskExecutable.path) {
            healthy = false
            lines.append("Missing scheduled executable: \(taskExecutable.path). Fix: usage-relay setup")
        }
        let output = record?.output ?? paths.defaultOutput
        lines.append("Output: \(output.path)")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
           let size = attributes[.size] as? NSNumber,
           let date = attributes[.modificationDate] as? Date {
            lines.append("Last publish: \(date), \(size) bytes")
        } else {
            healthy = false
            lines.append("Missing output. Fix: usage-relay setup --output FILE")
        }
        let status = statusline.status()
        let capture = statusline.lastCapture()
        let freshness = capture.map { Date().timeIntervalSince($0) < 24 * 3600 ? "recent" : "stale" } ?? "none"
        lines.append("Statusline: \(status); last capture: \(capture.map { String(describing: $0) } ?? "none") (\(freshness))")
        if hasClaude && status != .installed {
            healthy = false
            lines.append("Missing Claude capture. Fix: usage-relay setup")
        }
        if hasClaude && statusline.lastCapture() == nil {
            healthy = false
            lines.append("No Claude capture yet. Fix: start a Claude Code session to generate one.")
        }
        if record?.schedulerInstalled == true {
            let exists: Bool
            switch paths.platform {
            case .windows: exists = executor.run(Self.schtasksPath(environment: paths.environment),
                                                 ["/Query", "/TN", record?.taskName ?? configuredTaskName]) == 0
            case .linux: exists = executor.run("/usr/bin/systemctl", ["--user", "is-enabled", "aimana-relay.timer"]) == 0
            case .macOS: exists = true
            }
            lines.append("Schedule: \(exists ? "installed" : "missing")")
            if !exists { healthy = false; lines.append("Missing schedule. Fix: usage-relay setup") }
        } else {
            lines.append("Schedule: not installed")
            if paths.platform != .macOS {
                healthy = false
                lines.append("Missing schedule. Fix: usage-relay setup (or add its crontab line on Linux)")
            }
        }
        if !hasClaude && !hasCodex {
            healthy = false
            lines.append("No source data found. Fix: run Claude Code or Codex, then usage-relay setup")
        }
        return (lines, healthy)
    }

    public func uninstall() throws -> [String] {
        var lines: [String] = []
        switch paths.platform {
        case .windows:
            _ = executor.run(Self.schtasksPath(environment: paths.environment),
                             ["/Delete", "/TN", loadRecord()?.taskName ?? configuredTaskName, "/F"])
            try? FileManager.default.removeItem(at: hiddenLauncher)
            lines.append("Windows scheduled task removed")
        case .linux:
            _ = executor.run("/usr/bin/systemctl", ["--user", "disable", "--now", "aimana-relay.timer"])
            try? FileManager.default.removeItem(at: timerFile)
            try? FileManager.default.removeItem(at: serviceFile)
            _ = executor.run("/usr/bin/systemctl", ["--user", "daemon-reload"])
            lines.append("systemd user timer removed")
        case .macOS: break
        }
        switch statusline.status() {
        case .installed: try statusline.uninstall(); lines.append("Previous Claude statusline restored")
        case .replacedElsewhere: statusline.forget(); lines.append("Claude statusline was changed elsewhere; left as found")
        case .notInstalled: break
        }
        try? FileManager.default.removeItem(at: recordFile)
        lines.append("Usage data kept")
        return lines
    }

    private func loadRecord() -> SetupRecord? {
        guard let data = try? Data(contentsOf: recordFile) else { return nil }
        return try? JSONDecoder().decode(SetupRecord.self, from: data)
    }

    public static func schtasksPath(environment: [String: String]) -> String {
        let root = environment["SystemRoot"] ?? "C:\\Windows"
        return URL(fileURLWithPath: root).appendingPathComponent("System32/schtasks.exe").path
    }

    public static func windowsTaskArguments(interval: Int, executable: URL, configuration: URL,
                                            taskName: String = taskName) -> [String] {
        ["/Create", "/SC", "MINUTE", "/MO", String(interval), "/TN", taskName,
         "/TR", "\"\(executable.path)\" --config \"\(configuration.path)\"", "/F"]
    }

    public static func linuxRunCommand(executable: URL, configuration: URL,
                                       quote: (String) -> String) -> String {
        "\(quote(executable.path)) run --config \(quote(configuration.path))"
    }

    public static func systemdService(executable: URL, configuration: URL) -> String {
        let command = linuxRunCommand(executable: executable, configuration: configuration, quote: systemdQuote)
        return "[Unit]\nDescription=AI·mana usage relay\n\n[Service]\nType=oneshot\nExecStart=\(command)\n"
    }

    public static func systemdTimer(interval: Int) -> String {
        """
        [Unit]
        Description=Publish AI·mana relay every \(interval) minutes

        [Timer]
        OnBootSec=1min
        OnUnitActiveSec=\(interval)min
        Persistent=true

        [Install]
        WantedBy=timers.target

        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    private static func systemdEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "%", with: "%%")
    }
    private static func systemdQuote(_ value: String) -> String { "\"\(systemdEscape(value))\"" }
}
