import Foundation
@testable import AImanaCore

/// A unique lock for each test so refreshes never resolve the app's real App Group.
func testSaveLock() -> FileLock {
    FileLock(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("aimana-snapshot-test-\(UUID().uuidString).lock"))
}
