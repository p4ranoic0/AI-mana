#if canImport(Darwin)
import AImanaCore
import Foundation

/// The LaunchAgent that ran the CLI relay before the Mac app existed. The app only detects it and shows how to
/// remove it; it never removes it on its own.
public enum LegacyRelayJob {
    public static var label: String { "\(AppGroup.keychainService).relay" }

    public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func isPlistInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(home: home).path)
    }

    /// `launchctl print` is read-only; exit status 0 means the job is loaded in this login session.
    public static func isLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The exact commands the user can run to stop and delete the old job.
    public static func removalCommand(uid: uid_t = getuid()) -> String {
        "launchctl bootout gui/\(uid)/\(label)\nrm ~/Library/LaunchAgents/\(label).plist"
    }
}
#endif
