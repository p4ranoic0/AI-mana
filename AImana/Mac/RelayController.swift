import AImanaCore
import Foundation
import Observation
import RelayKit
import ServiceManagement

/// User choices, stored in the app's defaults. Debug runs can redirect output with launch arguments
/// (`-AImanaOutputPath <file>`, `-AImanaStateDir <dir>`, `-AImanaCacheDir <dir>`), which land in the arguments domain of `UserDefaults`.
enum MacSettings {
    static let refreshMinutesKey = "refreshMinutes"
    static let outputPathKey = "AImanaOutputPath"
    static let stateDirKey = "AImanaStateDir"
    static let cacheDirKey = "AImanaCacheDir"
    static let refreshChoices = [1, 5, 15]
    static let defaultRefreshMinutes = 5
}

@MainActor @Observable
final class RelayController {
    let isDemo: Bool
    private(set) var envelope: RelayEnvelope?
    private(set) var lastPublish: Date?
    private(set) var lastError: String?
    private(set) var isPublishing = false
    private(set) var statuslineStatus: StatuslineInstaller.Status = .notInstalled
    private(set) var statuslineMessage: String?
    private(set) var lastStatuslineCapture: Date?
    private(set) var legacyJobLoaded = false
    private(set) var legacyJobInstalled = false
    private(set) var launchAtLoginEnabled = false

    var refreshMinutes: Int {
        didSet {
            guard !isDemo else { return }
            defaults.set(refreshMinutes, forKey: MacSettings.refreshMinutesKey)
            restartLoop()
        }
    }
    var sourceEnabled: [String: Bool] = [:]

    func setSource(_ id: String, enabled: Bool) {
        guard !isDemo else { return }
        sourceEnabled[id] = enabled
        if let key = MacSourceConfiguration.defaultsKeys[id] { defaults.set(enabled, forKey: key) }
        publishSoon()
    }

    let output: URL
    let paths: RelayPaths
    let installer: StatuslineInstaller
    let notifier: MacNotifier
    /// True when a launch argument redirected publishing (debug runs never touch iCloud Drive).
    let isRedirected: Bool

    private let defaults: UserDefaults
    private var loop: Task<Void, Never>?
    private var watcher: StatuslineWatcher?
    private var statuslinePublish: Task<Void, Never>?
    private var lastPublishStart: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
        var paths = RelayPaths.standard
        if let dir = defaults.string(forKey: MacSettings.stateDirKey), !dir.isEmpty {
            paths.stateDirectory = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }
        if let dir = defaults.string(forKey: MacSettings.cacheDirKey), !dir.isEmpty {
            paths.caches = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }
        self.paths = paths
        if let out = defaults.string(forKey: MacSettings.outputPathKey), !out.isEmpty {
            output = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
            isRedirected = true
        } else {
            output = RelayPaths.defaultOutput
            isRedirected = false
        }
        installer = StatuslineInstaller(paths: paths)
        notifier = MacNotifier(stateDirectory: paths.stateDirectory, output: output, isDemo: isDemo)
        let stored = isDemo ? MacSettings.defaultRefreshMinutes : defaults.integer(forKey: MacSettings.refreshMinutesKey)
        refreshMinutes = MacSettings.refreshChoices.contains(stored) ? stored : MacSettings.defaultRefreshMinutes
        sourceEnabled = isDemo ? [:] : MacSourceConfiguration.defaultsKeys.mapValues { defaults.bool(forKey: $0) }
        if isDemo {
            envelope = DemoProviders.macEnvelope()
            lastPublish = envelope?.generatedAt
            return
        }
        envelope = try? RelayEnvelope.decode(Data(contentsOf: output))
        lastPublish = envelope?.generatedAt
        refreshStatus()
        restartLoop()
        startStatuslineWatcher()
        // One-shot setup from the terminal (`open -a AImana --args -register-login-item`), same as the Settings toggle.
        if ProcessInfo.processInfo.arguments.contains("-register-login-item") { setLaunchAtLogin(true) }
    }

    // MARK: Publishing

    private func restartLoop() {
        loop?.cancel()
        let minutes = refreshMinutes
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.publishNow()
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            }
        }
    }

    private func publishSoon() {
        Task { await publishNow() }
    }

    func publishNow(refreshOptional: Bool = true) async {
        guard !isDemo else { return }
        guard !isPublishing else { return }
        isPublishing = true
        lastPublishStart = Date()
        defer { isPublishing = false }
        let options = MacSourceConfiguration.options(output: output, enabled: sourceEnabled,
                                                     refreshOptional: refreshOptional)
        let publisher = RelayPublisher(paths: paths, log: { NSLog("[AImana] %@", $0) },
                                       endpoints: MacSourceConfiguration.endpoints(paths: paths))
        do {
            let report = try await Task.detached(priority: .utility) { try await publisher.publish(options) }.value
            envelope = report.envelope
            lastPublish = report.finishedAt
            lastError = nil
            await notifier.didPublish(report)
        } catch RelayPublishError.busy {
            lastError = String(localized: "Another relay is publishing right now.")
        } catch {
            lastError = String(localized: "Could not write the file.")
        }
        refreshStatus()
    }

    // MARK: Statusline freshness

    /// Claude Code rewrites the capture file on every message. Publishing soon after (at most every 30 s, 60 s when
    /// the Claude endpoint is on, since each publish then calls it) makes threshold alerts near-instant instead of
    /// waiting for the next timer tick. The watch is a kernel event: nothing runs while Claude Code is idle.
    private func startStatuslineWatcher() {
        let watcher = StatuslineWatcher(file: paths.claudeStatuslineFile) { [weak self] _ in
            Task { @MainActor in self?.statuslineChanged() }
        }
        if watcher.start() { self.watcher = watcher }
    }

    private func statuslineChanged() {
        lastStatuslineCapture = installer.lastCapture()
        guard statuslinePublish == nil else { return }   // one is already scheduled and will read the newest file
        let delay = PublishDebounce.delay(lastPublishStart: lastPublishStart, now: Date(),
                                          minInterval: MacSourceConfiguration.debounceInterval(enabled: sourceEnabled))
        statuslinePublish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while self?.isPublishing == true { try? await Task.sleep(for: .seconds(1)) }
            await self?.publishNow(refreshOptional: false)
            self?.statuslinePublish = nil
        }
    }

    // MARK: Status

    func refreshStatus() {
        guard !isDemo else { return }
        statuslineStatus = installer.status()
        lastStatuslineCapture = installer.lastCapture()
        legacyJobInstalled = LegacyRelayJob.isPlistInstalled()
        legacyJobLoaded = LegacyRelayJob.isLoaded()
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    var enabledOptionalProviders: [String] {
        MacSourceConfiguration.optionalProviders.filter { sourceEnabled[$0] == true }
    }

    func entry(_ providerID: String) -> RelayEntry? {
        envelope?.entries.first { $0.providerID == providerID }
    }

    func cost(_ providerID: String, days: Int, now: Date = Date()) -> CostTotal? {
        guard let report = envelope?.costs.first(where: { $0.providerID == providerID }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return report.total(lastDays: days, endingOn: f.string(from: now))
    }

    var iCloudDriveAvailable: Bool {
        if isDemo { return false }
        return FileManager.default.fileExists(atPath: output.deletingLastPathComponent().deletingLastPathComponent().path)
    }

    // MARK: Statusline

    func installStatusline() {
        guard !isDemo else { return }
        statuslineMessage = Self.describe { try installer.install() }
        refreshStatus()
    }

    func uninstallStatusline() {
        guard !isDemo else { return }
        statuslineMessage = Self.describe { try installer.uninstall() }
        refreshStatus()
    }

    func forgetStatusline() {
        guard !isDemo else { return }
        installer.forget()
        statuslineMessage = nil
        refreshStatus()
    }

    private static func describe(_ action: () throws -> Void) -> String? {
        do {
            try action()
            return nil
        } catch let error as StatuslineInstaller.InstallError {
            switch error {
            case .settingsUnreadable: return String(localized: "Claude Code's settings.json could not be read as JSON. Nothing was changed.")
            case .concurrentModification: return String(localized: "settings.json changed while installing. Nothing was changed; try again.")
            case .notInstalled: return String(localized: "The wrapper is not installed.")
            case .replacedElsewhere: return String(localized: "The statusline was changed outside AImana, so it was left as it is.")
            case .validationFailed: return String(localized: "The edit could not be verified. Nothing was changed.")
            case .writeFailed: return String(localized: "Could not write the file.")
            }
        } catch {
            return String(localized: "Could not write the file.")
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[AImana] launch at login: %@", String(describing: error))
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}
