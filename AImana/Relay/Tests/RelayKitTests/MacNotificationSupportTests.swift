import AImanaCore
import Foundation
import Testing
@testable import RelayKit

@Suite struct MacNotificationSupportTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_700_000)

    @Test func endpointOutcomesMapToMacAccess() {
        let report = PublishReport(envelope: RelayEnvelope(generatedAt: t0, entries: []),
                                   output: URL(fileURLWithPath: "/dev/null"), finishedAt: t0,
                                   endpoints: ["claude": .failure(.unauthenticated), "codex": .success])
        #expect(report.macLogins(providerIDs: ["claude", "codex"]) == ["claude": .expired, "codex": .active])

        let other = PublishReport(envelope: RelayEnvelope(generatedAt: t0, entries: []),
                                  output: URL(fileURLWithPath: "/dev/null"), finishedAt: t0,
                                  endpoints: ["claude": .failure(.network)])
        // A network failure says nothing; an endpoint that was not asked clears any old alert.
        #expect(other.macLogins(providerIDs: ["claude", "codex"]) == ["codex": .signedOut])
    }

    @Test func debounceWaitsForTheMinimumInterval() {
        #expect(PublishDebounce.delay(lastPublishStart: nil, now: t0) == PublishDebounce.settle)
        #expect(PublishDebounce.delay(lastPublishStart: t0, now: t0.addingTimeInterval(10)) == 20)
        #expect(PublishDebounce.delay(lastPublishStart: t0, now: t0.addingTimeInterval(29)) == PublishDebounce.settle)
        #expect(PublishDebounce.delay(lastPublishStart: t0, now: t0.addingTimeInterval(600)) == PublishDebounce.settle)
        #expect(PublishDebounce.delay(lastPublishStart: t0, now: t0, minInterval: 60) == 60)
    }

    #if !os(Linux)
    @Test func watcherFiresOnAtomicReplaceButNotOnOtherFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("claude-statusline.json")
        let hits = Counter()
        let watcher = StatuslineWatcher(file: file) { _ in hits.increment() }
        #expect(watcher.start())

        // Another file in the same directory (history, lock) is ignored.
        try Data("x".utf8).write(to: dir.appendingPathComponent("history.json"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(hits.value == 0)

        // The wrapper's temp file + mv.
        let tmp = dir.appendingPathComponent("claude-statusline.json.123.tmp")
        try Data("{}".utf8).write(to: tmp)
        #expect(rename(tmp.path, file.path) == 0)
        try await waitUntil { hits.value >= 1 }
        #expect(hits.value == 1)

        // A later rewrite with a new modification date fires again.
        try Data("{\"a\":1}".utf8).write(to: tmp)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: tmp.path)
        #expect(rename(tmp.path, file.path) == 0)
        try await waitUntil { hits.value >= 2 }
        watcher.stop()
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<50 where !condition() { try await Task.sleep(for: .milliseconds(100)) }
        #expect(condition())
    }
    #endif
}

#if !os(Linux)
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
#endif
