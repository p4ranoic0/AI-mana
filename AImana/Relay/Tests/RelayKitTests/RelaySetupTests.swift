import AImanaCore
import Foundation
import Testing
@testable import RelayKit

private final class RecordingExecutor: RelayCommandExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, [String])] = []
    var systemdAvailable = true
    var calls: [(String, [String])] { lock.withLock { entries } }
    func run(_ executable: String, _ arguments: [String]) -> Int32 {
        lock.withLock { entries.append((executable, arguments)) }
        if arguments == ["--user", "show-environment"] { return systemdAvailable ? 0 : 1 }
        return 0
    }
}

@Suite struct RelaySetupTests {
    @Test func platformPathsAndOutputPrecedence() throws {
        let home = try makeTempDir()
        let local = home.appendingPathComponent("AppData/Local")
        let cloud = home.appendingPathComponent("OneDrive")
        let windows = RelayPaths(home: home, environment: ["LOCALAPPDATA": local.path, "OneDrive": cloud.path,
                                                          "CLAUDE_CONFIG_DIR": home.appendingPathComponent("custom claude").path,
                                                          "CODEX_HOME": home.appendingPathComponent("custom codex").path],
                                 platform: .windows)
        #expect(windows.supportDirectory.path == local.appendingPathComponent("AImana").path)
        #expect(windows.stateDirectory == windows.supportDirectory)
        #expect(windows.caches.path == local.appendingPathComponent("AImana/Cache").path)
        #expect(windows.claudeProjectRoots == [home.appendingPathComponent("custom claude/projects")])
        #expect(windows.codexSessionRoots == [home.appendingPathComponent("custom codex/sessions")])
        #expect(windows.defaultOutput == cloud.appendingPathComponent("AImana/usage-relay.json"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("iCloudDrive"), withIntermediateDirectories: true)
        #expect(windows.defaultOutput == home.appendingPathComponent("iCloudDrive/AImana/usage-relay.json"))
        let plain = RelayPaths(home: home, platform: .windows)
        #expect(plain.defaultOutput == home.appendingPathComponent("iCloudDrive/AImana/usage-relay.json"))
        let linux = RelayPaths(home: home, environment: ["XDG_DATA_HOME": home.appendingPathComponent("data").path],
                               platform: .linux)
        #expect(linux.supportDirectory.path == home.appendingPathComponent("data/aimana").path)
        #expect(linux.defaultOutput == home.appendingPathComponent("AImana/usage-relay.json"))
    }

    @Test func parsesSetupArguments() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("out.json").path
        #expect(try SetupOptions(arguments: []).interval == 5)
        #expect(try SetupOptions(arguments: ["--interval", "1"]).interval == 1)
        #expect(try SetupOptions(arguments: ["--output", output]).output?.path == output)
        for args in [["--interval", "0"], ["--interval", "abc"], ["--output"], ["--unknown", "x"]] {
            #expect(throws: SetupError.invalidArguments) { try SetupOptions(arguments: args) }
        }
    }

    @Test func stablePackageManagerPaths() {
        let brew = "/opt/homebrew/Cellar/usage-relay/1.2.3/bin/usage-relay"
        let brewStable = "/opt/homebrew/opt/usage-relay/bin/usage-relay"
        #expect(RelayExecutable.stablePath(brew, exists: { $0 == brewStable }) == brewStable)
        #expect(RelayExecutable.stablePath(brew, exists: { _ in false }) == brew)
        let scoop = #"C:\Users\me\scoop\apps\usage-relay\1.2.3\usage-relay.exe"#
        let scoopStable = #"C:\Users\me\scoop\apps\usage-relay\current\usage-relay.exe"#
        #expect(RelayExecutable.stablePath(scoop, exists: { $0 == scoopStable }) == scoopStable)
        #expect(RelayExecutable.stablePath(scoop, exists: { _ in false }) == scoop)
        #expect(RelayExecutable.stablePath("/usr/local/bin/usage-relay", exists: { _ in true }) == "/usr/local/bin/usage-relay")
    }

    @Test func setupInstallsStableExecutableEverywhere() async throws {
        let home = try makeTempDir()
        let versioned = home.appendingPathComponent("brew/Cellar/usage-relay/1.2.3/bin/usage-relay")
        let stable = home.appendingPathComponent("brew/opt/usage-relay/bin/usage-relay")
        try FileManager.default.createDirectory(at: stable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: stable)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        let setup = RelaySetup(paths: RelayPaths(home: home, platform: .linux), executable: versioned,
                               executor: RecordingExecutor(), publish: { _ in })
        _ = try await setup.setup(SetupOptions(arguments: []))
        #expect(setup.executable == stable)
        #expect(setup.statusline.executable == stable)
        #expect(try String(contentsOf: setup.serviceFile, encoding: .utf8).contains(stable.path))
        #expect(try String(contentsOf: setup.statusline.scriptFile, encoding: .utf8).contains(stable.path))
        let record = try JSONDecoder().decode(SetupRecord.self, from: Data(contentsOf: setup.recordFile))
        #expect(record.executable == stable)
    }

    @Test func windowsScheduleAndUninstallUseInjectedExecutor() async throws {
        let home = try makeTempDir()
        let output = home.appendingPathComponent("OneDrive/AImana/usage-relay.json")
        let taskName = "AImanaUsageRelayTest"
        let paths = RelayPaths(home: home, supportDirectory: home.appendingPathComponent("support"),
                               environment: ["AIMANA_TASK_NAME": taskName], platform: .windows)
        let executor = RecordingExecutor()
        let relay = home.appendingPathComponent("bin/usage-relay.exe")
        let task = relay.deletingLastPathComponent().appendingPathComponent("usage-relay-task.exe")
        try FileManager.default.createDirectory(at: task.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: task)
        let setup = RelaySetup(paths: paths, executable: relay, executor: executor, publish: { _ in })
        let lines = try await setup.setup(SetupOptions(arguments: ["--output", output.path, "--interval", "7"]))
        #expect(lines.contains { $0.contains("Published:") })
        #expect(executor.calls[0].1 == RelaySetup.windowsTaskArguments(interval: 7, executable: task,
                                                                      configuration: setup.recordFile, taskName: taskName))
        #expect(executor.calls[0].0.hasSuffix("schtasks.exe"))
        #expect(!FileManager.default.fileExists(atPath: setup.hiddenLauncher.path))
        let record = try JSONDecoder().decode(SetupRecord.self, from: Data(contentsOf: setup.recordFile))
        #expect(record.interval == 7 && record.output == output && record.schedulerInstalled)
        #expect(record.executable == relay && record.taskExecutable == task && record.taskName == taskName)
        let restored = try #require(record.taskConfiguration?.relayPaths())
        #expect(restored.home == paths.home && restored.stateDirectory == paths.stateDirectory)
        #expect(restored.supportDirectory == paths.supportDirectory && restored.caches == paths.caches)
        #expect(restored.claudeProjectRoots == paths.claudeProjectRoots)
        #expect(restored.codexSessionRoots == paths.codexSessionRoots)
        try Data("legacy".utf8).write(to: setup.hiddenLauncher)
        _ = try setup.uninstall()
        #expect(executor.calls.last?.1 == ["/Delete", "/TN", taskName, "/F"])
        #expect(!FileManager.default.fileExists(atPath: setup.recordFile.path))
        #expect(!FileManager.default.fileExists(atPath: setup.hiddenLauncher.path))
    }

    @Test func doctorReportsMissingRecordedExecutable() async throws {
        let home = try makeTempDir()
        let paths = RelayPaths(home: home, supportDirectory: home.appendingPathComponent("support"), platform: .windows)
        let relay = home.appendingPathComponent("bin/usage-relay.exe")
        let task = home.appendingPathComponent("bin/usage-relay-task.exe")
        try FileManager.default.createDirectory(at: relay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: relay)
        try Data().write(to: task)
        let setup = RelaySetup(paths: paths, executable: relay, executor: RecordingExecutor(), publish: { _ in })
        _ = try await setup.setup(SetupOptions(arguments: []))
        try FileManager.default.removeItem(at: relay)
        try FileManager.default.removeItem(at: task)
        let result = setup.doctor()
        #expect(!result.healthy)
        #expect(result.lines.contains { $0.contains("Missing recorded executable:") && $0.contains("usage-relay setup") })
        #expect(result.lines.contains { $0.contains("Missing scheduled executable:") && $0.contains("usage-relay setup") })
    }

    @Test func taskConfigurationKeepsInjectedSourceAndCapturePaths() async throws {
        let home = try makeTempDir()
        var paths = RelayPaths(home: home, stateDirectory: home.appendingPathComponent("state"),
                               caches: home.appendingPathComponent("cache"),
                               supportDirectory: home.appendingPathComponent("support"),
                               environment: ["CLAUDE_CONFIG_DIR": home.appendingPathComponent("claude custom").path,
                                             "CODEX_HOME": home.appendingPathComponent("codex custom").path,
                                             "LOCALAPPDATA": home.appendingPathComponent("local").path,
                                             "UNRELATED_SECRET": "not persisted"], platform: .windows)
        paths.claudeStatuslineFile = home.appendingPathComponent("capture/statusline.json")
        let encoded = try JSONEncoder().encode(RelayTaskConfiguration(paths: paths))
        let restored = try JSONDecoder().decode(RelayTaskConfiguration.self, from: encoded).relayPaths()
        #expect(restored.claudeProjectRoots == paths.claudeProjectRoots)
        #expect(restored.codexSessionRoots == paths.codexSessionRoots)
        #expect(restored.claudeStatuslineFile == paths.claudeStatuslineFile)
        #expect(restored.stateDirectory == paths.stateDirectory)
        #expect(restored.caches == paths.caches)
        #expect(restored.environment["UNRELATED_SECRET"] == nil)
        let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: restored.claudeProjectRoots[0], withIntermediateDirectories: true)
        let session = restored.codexSessionRoots[0].appendingPathComponent("2026/10/12/session.jsonl")
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: fixtureDirectory.appendingPathComponent("codex-session.jsonl")).write(to: session)
        _ = try StatuslineCapture.save(Data(contentsOf: fixtureDirectory.appendingPathComponent("statusline.json")),
                                       to: restored.claudeStatuslineFile)
        let report = try await RelayRun.publish(paths: restored,
                                                options: RelayOptions(output: home.appendingPathComponent("out/usage-relay.json"),
                                                                      includeCosts: false))
        #expect(report.envelope.entries.first(where: { $0.providerID == "claude" })?.usage?.windows.first?.usedPercent == 23)
        #expect(report.envelope.entries.first(where: { $0.providerID == "codex" })?.usage?.windows.first?.usedPercent == 15)
    }

    @Test func ciStatuslineFixtureBecomesClaudeUsage() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/statusline.json")
        let capture = try makeTempDir().appendingPathComponent("claude-statusline.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try StatuslineCapture.save(Data(contentsOf: fixture), to: capture, now: now) == "CI Opus")
        let usage = try ClaudeStatuslineSource.usage(from: Data(contentsOf: capture), now: now)
        #expect(usage.windows.first?.usedPercent == 23)
    }

    @Test func linuxTimerAndFallbackCommands() async throws {
        let home = try makeTempDir()
        let paths = RelayPaths(home: home, platform: .linux)
        let executor = RecordingExecutor()
        let setup = RelaySetup(paths: paths, executable: home.appendingPathComponent("relay"), executor: executor,
                               publish: { _ in })
        _ = try await setup.setup(SetupOptions(arguments: []))
        #expect(executor.calls.map(\.1) == [["--user", "show-environment"], ["--user", "daemon-reload"],
                                          ["--user", "enable", "--now", "aimana-relay.timer"]])
        #expect(try String(contentsOf: setup.serviceFile, encoding: .utf8).contains("ExecStart="))
        #expect(try String(contentsOf: setup.timerFile, encoding: .utf8).contains("OnUnitActiveSec=5min"))
        _ = try setup.uninstall()
        #expect(executor.calls.suffix(2).map(\.1) == [["--user", "disable", "--now", "aimana-relay.timer"],
                                                   ["--user", "daemon-reload"]])

        let unavailable = RecordingExecutor()
        unavailable.systemdAvailable = false
        let fallback = RelaySetup(paths: paths, executable: home.appendingPathComponent("relay"), executor: unavailable,
                                  publish: { _ in })
        let lines = try await fallback.setup(SetupOptions(arguments: []))
        #expect(lines.contains { $0.contains("*/5 * * * *") })
        #expect(unavailable.calls.count == 1)
    }

    @Test func windowsSettingsRestoreAndCapture() throws {
        let home = try makeTempDir()
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"statusLine":{"type":"command","command":"echo old"},"model":"opus"}"#
        try Data(original.utf8).write(to: settings)
        let support = home.appendingPathComponent("support")
        let installer = StatuslineInstaller(settingsFile: settings, supportDirectory: support,
                                            dataFile: support.appendingPathComponent(ClaudeStatuslineSource.fileName),
                                            platform: .windows, executable: home.appendingPathComponent("usage-relay.exe"))
        try installer.install()
        #expect(installer.command.contains("powershell.exe"))
        #expect(try String(contentsOf: installer.scriptFile, encoding: .utf8).contains("statusline-capture"))
        #expect(installer.status() == .installed)
        try installer.uninstall()
        #expect(try String(contentsOf: settings, encoding: .utf8) == original)

        let file = support.appendingPathComponent(ClaudeStatuslineSource.fileName)
        let input = Data(#"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23}}}"#.utf8)
        #expect(try StatuslineCapture.save(input, to: file, now: Date(timeIntervalSince1970: 1000)) == "Opus")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        #expect(saved?["capturedAt"] as? Double == 1000)
        #expect(saved?["model"] == nil)
        let before = try Data(contentsOf: file)
        #expect(try StatuslineCapture.save(Data(#"{"model":{"display_name":"Sonnet"}}"#.utf8), to: file) == "Sonnet")
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func windowsWithoutPriorStatuslineRunsRelayDirectly() throws {
        let home = try makeTempDir()
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: settings)
        let support = home.appendingPathComponent("support")
        let relay = home.appendingPathComponent("usage-relay.exe")
        let installer = StatuslineInstaller(settingsFile: settings, supportDirectory: support,
                                            dataFile: support.appendingPathComponent(ClaudeStatuslineSource.fileName),
                                            platform: .windows, executable: relay)
        try installer.install()
        let content = try Data(contentsOf: settings)
        let object = try #require(JSONSerialization.jsonObject(with: content) as? [String: Any])
        let status = try #require(object["statusLine"] as? [String: Any])
        #expect(status["command"] as? String == "\"\(relay.path)\" statusline-capture")
        #expect(installer.status() == .installed)
        #expect(!FileManager.default.fileExists(atPath: installer.scriptFile.path))
        let moved = home.appendingPathComponent("new/usage-relay.exe")
        let refreshed = StatuslineInstaller(settingsFile: settings, supportDirectory: support,
                                            dataFile: support.appendingPathComponent(ClaudeStatuslineSource.fileName),
                                            platform: .windows, executable: moved)
        try refreshed.install()
        #expect(refreshed.status() == .installed)
        #expect(try String(contentsOf: settings, encoding: .utf8).contains(moved.path))
        try refreshed.uninstall()
        #expect(try String(contentsOf: settings, encoding: .utf8) == #"{"model":"opus"}"#)
    }
}
