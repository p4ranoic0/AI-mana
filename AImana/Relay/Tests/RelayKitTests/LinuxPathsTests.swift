#if os(Linux)
import Foundation
import Testing
@testable import RelayKit

@Suite struct LinuxPathsTests {
    private let home = URL(fileURLWithPath: "/tmp/relay-linux-home", isDirectory: true)

    @Test func xdgDefaultsAndOverrides() {
        let defaults = RelayPaths(home: home)
        #expect(defaults.supportDirectory.path == "/tmp/relay-linux-home/.local/share/aimana")
        #expect(defaults.stateDirectory == defaults.supportDirectory)
        #expect(defaults.caches.path == "/tmp/relay-linux-home/.cache/aimana")
        #expect(defaults.claudeStatuslineFile.deletingLastPathComponent() == defaults.supportDirectory)

        let custom = RelayPaths(home: home, environment: [
            "XDG_DATA_HOME": "/tmp/xdg-data", "XDG_CACHE_HOME": "/tmp/xdg-cache",
        ])
        #expect(custom.supportDirectory.path == "/tmp/xdg-data/aimana")
        #expect(custom.stateDirectory == custom.supportDirectory)
        #expect(custom.caches.path == "/tmp/xdg-cache/aimana")
    }

    @Test func explicitPathsWinOverXdg() {
        let state = home.appendingPathComponent("state")
        let caches = home.appendingPathComponent("caches")
        let support = home.appendingPathComponent("support")
        let paths = RelayPaths(home: home, stateDirectory: state, caches: caches, supportDirectory: support,
                               environment: ["XDG_DATA_HOME": "/tmp/xdg-data", "XDG_CACHE_HOME": "/tmp/xdg-cache"])
        #expect(paths.stateDirectory == state)
        #expect(paths.caches == caches)
        #expect(paths.supportDirectory == support)
    }

    @Test func defaultOutputLivesUnderHome() {
        #expect(RelayPaths.defaultOutput.path == FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AImana/usage-relay.json").path)
    }
}
#endif
