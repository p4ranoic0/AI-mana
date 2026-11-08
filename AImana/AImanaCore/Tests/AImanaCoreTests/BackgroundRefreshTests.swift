#if canImport(AImanaSignIn)
import Foundation
import Testing
@testable import AImanaCore
@testable import AImanaSignIn

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Answers token requests through a closure, after an optional delay that lets two callers overlap.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private let reply: @Sendable (URLRequest) -> (Int, String)
    private var sent: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { sent } }

    init(delay: TimeInterval = 0, reply: @escaping @Sendable (URLRequest) -> (Int, String)) {
        self.delay = delay
        self.reply = reply
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let (status, body) = reply(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }

    static func refreshToken(of request: URLRequest) -> String? {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])?["refresh_token"]
    }
}

private func tempLockURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("aimana-test-\(UUID().uuidString).lock")
}

private func put<S: Encodable>(_ session: S, key: String, in store: InMemoryCredentialStore) throws {
    try store.write(String(decoding: try JSONEncoder().encode(session), as: UTF8.self), for: key)
}

private func claudeSession(in store: InMemoryCredentialStore) throws -> ClaudeSession? {
    try store.read(PhoneClaudeTokens.storeKey).map { try JSONDecoder().decode(ClaudeSession.self, from: Data($0.utf8)) }
}

@Suite struct FileLockTests {
    @Test func rejectsTheRealGroupContainerPathDuringTests() {
        #if DEBUG
        #expect(FileLock.isRunningTests, "\(ProcessInfo.processInfo.processName) | \(CommandLine.arguments)")
        #endif
        let group = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.example.aimana")
        #expect(FileLock.isUserGroupContainer(group.appendingPathComponent("snapshot-save.lock")))
        #expect(!FileLock.isUserGroupContainer(tempLockURL()))
    }

    @Test func secondHolderWaitsAndTimesOut() async throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = FileLock(url: url)
        let second = FileLock(url: url, timeout: 0.2)
        try await first.withLock {
            await #expect(throws: ProcessLockError.timedOut) { try await second.withLock { } }
        }
        #expect(try await second.withLock { 42 } == 42)   // released after the first body returned
    }

    @Test func bodiesNeverOverlap() async throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        final class Counter: @unchecked Sendable {
            let lock = NSLock(); var inside = 0; var maxInside = 0
            func enter() { lock.withLock { inside += 1; maxInside = max(maxInside, inside) } }
            func leave() { lock.withLock { inside -= 1 } }
        }
        let counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await FileLock(url: url).withLock {
                        counter.enter()
                        try await Task.sleep(nanoseconds: 30_000_000)
                        counter.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(counter.maxInside == 1)
    }

    @Test func throwingBodyStillReleases() async throws {
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: UsageProviderError.network) {
            try await FileLock(url: url).withLock { throw UsageProviderError.network }
        }
        #expect(try await FileLock(url: url, timeout: 0.2).withLock { true })
    }
}

/// The app and the widget each own a token manager over the same Keychain item; these play both.
@Suite struct CrossProcessRenewalTests {
    @Test func twoManagersRedeemTheRotatingTokenOnce() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let reply: @Sendable (URLRequest) -> (Int, String) = { request in
            ScriptedTransport.refreshToken(of: request) == "R"
                ? (200, #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#)
                : (400, #"{"error":"invalid_grant"}"#)   // a consumed refresh token kills the session
        }
        let appTransport = ScriptedTransport(delay: 0.15, reply: reply)
        let widgetTransport = ScriptedTransport(delay: 0.15, reply: reply)
        let app = PhoneClaudeTokens(store: store, transport: appTransport, clock: { t0 }, processLock: FileLock(url: url))
        let widget = PhoneClaudeTokens(store: store, transport: widgetTransport, clock: { t0 },
                                       processLock: FileLock(url: url))
        async let a = app.credentials()
        async let b = widget.credentials()
        let (fromApp, fromWidget) = try await (a, b)
        #expect(fromApp.token == "A2" && fromWidget.token == "A2")
        #expect(appTransport.requests.count + widgetTransport.requests.count == 1)
        #expect(try claudeSession(in: store)?.refreshToken == "R2")
    }

    @Test func twoCodexManagersRedeemTheRotatingTokenOnce() async throws {
        let store = InMemoryCredentialStore()
        try put(CodexSession(accessToken: "A", refreshToken: "R", accountID: "acct", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneCodexTokens.storeKey, in: store)
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let reply: @Sendable (URLRequest) -> (Int, String) = { request in
            ScriptedTransport.refreshToken(of: request) == "R"
                ? (200, #"{"access_token":"A2","refresh_token":"R2","expires_in":3600}"#)
                : (400, #"{"error":"invalid_grant"}"#)
        }
        let first = ScriptedTransport(delay: 0.15, reply: reply)
        let second = ScriptedTransport(delay: 0.15, reply: reply)
        let app = PhoneCodexTokens(store: store, transport: first, clock: { t0 }, processLock: FileLock(url: url))
        let widget = PhoneCodexTokens(store: store, transport: second, clock: { t0 }, processLock: FileLock(url: url))
        async let a = app.credentials()
        async let b = widget.credentials()
        let (x, y) = try await (a, b)
        #expect(x.token == "A2" && y.token == "A2" && y.accountID == "acct")
        #expect(first.requests.count + second.requests.count == 1)
    }

    @Test func invalidGrantRereadsTheStoreBeforeGivingUp() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        // Another process rotated the token while this request was in flight, then the server rejected "R".
        let transport = ScriptedTransport { _ in
            try? put(ClaudeSession(accessToken: "A3", refreshToken: "R3", expiresAt: t0.addingTimeInterval(8 * 3600)),
                     key: PhoneClaudeTokens.storeKey, in: store)
            return (400, #"{"error":"invalid_grant"}"#)
        }
        let tokens = PhoneClaudeTokens(store: store, transport: transport, clock: { t0 }, processLock: NoProcessLock())
        #expect(try await tokens.credentials().token == "A3")
        #expect(transport.requests.count == 1)
    }

    @Test func invalidGrantRetriesOnceWithTheNewerToken() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        let transport = ScriptedTransport { request in
            if ScriptedTransport.refreshToken(of: request) == "R3" {
                return (200, #"{"access_token":"A4","refresh_token":"R4","expires_in":28800}"#)
            }
            // Rotated elsewhere, but that session is already close to expiring too.
            try? put(ClaudeSession(accessToken: "A3", refreshToken: "R3", expiresAt: t0.addingTimeInterval(10)),
                     key: PhoneClaudeTokens.storeKey, in: store)
            return (400, #"{"error":"invalid_grant"}"#)
        }
        let tokens = PhoneClaudeTokens(store: store, transport: transport, clock: { t0 })
        #expect(try await tokens.credentials().token == "A4")
        #expect(try claudeSession(in: store)?.refreshToken == "R4")
        #expect(transport.requests.count == 2)
    }

    @Test func invalidGrantWithNothingNewerIsUnauthenticated() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        let transport = ScriptedTransport { _ in (400, #"{"error":"invalid_grant"}"#) }
        let tokens = PhoneClaudeTokens(store: store, transport: transport, clock: { t0 })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
        #expect(transport.requests.count == 1)
    }

    @Test func signOutDuringRenewalIsNotUndone() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        let transport = ScriptedTransport { _ in
            try? store.delete(PhoneClaudeTokens.storeKey)   // the user signed out in the app meanwhile
            return (200, #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#)
        }
        let tokens = PhoneClaudeTokens(store: store, transport: transport, clock: { t0 })
        await #expect(throws: UsageProviderError.unauthenticated) { _ = try await tokens.credentials() }
        #expect(!tokens.isSignedIn)
    }

    @Test func busyLockIsTransientAndSendsNothing() async throws {
        let store = InMemoryCredentialStore()
        try put(ClaudeSession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(-5)),
                key: PhoneClaudeTokens.storeKey, in: store)
        let url = tempLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = ScriptedTransport { _ in (200, #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#) }
        let tokens = PhoneClaudeTokens(store: store, transport: transport, clock: { t0 },
                                       processLock: FileLock(url: url, timeout: 0.2))
        try await FileLock(url: url).withLock {
            await #expect(throws: UsageProviderError.network) { _ = try await tokens.credentials() }
        }
        #expect(transport.requests.isEmpty)
        #expect(try claudeSession(in: store)?.refreshToken == "R")
    }
}

@Suite struct RefreshScheduleTests {
    private func info(_ id: String, age: TimeInterval) -> UsageInfo {
        UsageInfo(providerID: id, providerName: id, windows: [], plan: nil, lastUpdated: t0.addingTimeInterval(-age))
    }

    @Test func intervalDefaultsToOneHourAndRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "aimana-test-\(UUID().uuidString)"))
        #expect(RefreshPreferences.interval(defaults: defaults) == .oneHour)
        RefreshPreferences.setInterval(.fifteenMinutes, defaults: defaults)
        #expect(RefreshPreferences.interval(defaults: defaults) == .fifteenMinutes)
        defaults.set(7, forKey: RefreshPreferences.intervalKey)   // not an offered choice
        #expect(RefreshPreferences.interval(defaults: defaults) == .oneHour)
        #expect(RefreshInterval.allCases.map(\.seconds) == [900, 1800, 3600, 7200, 14400])
        #expect(RefreshInterval.allCases.allSatisfy { !$0.title.isEmpty && !$0.title.hasPrefix("refresh.") })
    }

    @Test func nothingToDoWithoutAPhoneSignIn() {
        #expect(!RefreshSchedule.isDue(snapshot: [], providerIDs: [], interval: .oneHour, lastAttempt: nil, now: t0))
    }

    @Test func dueWhenTheSnapshotIsOldOrMissing() {
        let old = [info("claude", age: 3600)]
        #expect(RefreshSchedule.isDue(snapshot: old, providerIDs: ["claude"], interval: .oneHour, lastAttempt: nil, now: t0))
        #expect(RefreshSchedule.isDue(snapshot: [], providerIDs: ["claude"], interval: .oneHour, lastAttempt: nil, now: t0))
        // The reload one interval later lands a moment before the saved reading is that old.
        let almost = [info("claude", age: 3600 - 30)]
        #expect(RefreshSchedule.isDue(snapshot: almost, providerIDs: ["claude"], interval: .oneHour, lastAttempt: nil, now: t0))
    }

    @Test func notDueWhileFresh() {
        let fresh = [info("claude", age: 10 * 60), info("codex", age: 20 * 60)]
        #expect(!RefreshSchedule.isDue(snapshot: fresh, providerIDs: ["claude", "codex"], interval: .oneHour,
                                       lastAttempt: nil, now: t0))
        #expect(RefreshSchedule.isDue(snapshot: fresh, providerIDs: ["claude", "codex"], interval: .fifteenMinutes,
                                      lastAttempt: nil, now: t0))
    }

    @Test func recentAttemptHoldsOtherWidgetsBack() {
        let old = [info("claude", age: 5 * 3600)]
        #expect(!RefreshSchedule.isDue(snapshot: old, providerIDs: ["claude"], interval: .oneHour,
                                       lastAttempt: t0.addingTimeInterval(-60), now: t0))
        #expect(RefreshSchedule.isDue(snapshot: old, providerIDs: ["claude"], interval: .oneHour,
                                      lastAttempt: t0.addingTimeInterval(-6 * 60), now: t0))
        // A clock moved backwards must not block refreshing for good.
        #expect(RefreshSchedule.isDue(snapshot: old, providerIDs: ["claude"], interval: .oneHour,
                                      lastAttempt: t0.addingTimeInterval(3600), now: t0))
    }
}

@Suite struct WidgetFetchMergeTests {
    private struct Live: UsageProvider {
        let id = "claude"
        let displayName = "Claude Code"
        func fetchUsage() async throws -> UsageInfo {
            UsageInfo(providerID: id, providerName: displayName,
                      windows: [UsageWindow(kind: .session, usedPercent: 40, windowMinutes: 300, resetsAt: nil)],
                      plan: nil, lastUpdated: t0)
        }
    }

    private let saved = UsageInfo(
        providerID: "claude", providerName: "Claude Code",
        windows: [UsageWindow(kind: .session, usedPercent: 10, windowMinutes: 300, resetsAt: nil)], plan: "Max",
        lastUpdated: t0.addingTimeInterval(-7200),
        cost: CostReport(providerID: "claude", generatedAt: t0.addingTimeInterval(-7200), days: []),
        history: [HistorySeries(providerID: "claude", kind: .weekly,
                                points: [HistoryPoint(t: t0.addingTimeInterval(-7200), used: 30, resetsAt: nil)])])

    @Test func directReadingKeepsTheSnapshotsRelayOnlyFields() async throws {
        let provider = HybridProvider(direct: Live(), relay: SnapshotProvider(id: "claude", displayName: "Claude Code",
                                                                              items: [saved]),
                                      isDirectEnabled: { true })
        let usage = try await provider.fetchUsage()
        #expect(usage.primary?.usedPercent == 40 && usage.lastUpdated == t0)
        #expect(usage.cost == saved.cost && usage.history == saved.history && usage.plan == "Max")
    }

    @Test func providerWithoutPhoneSignInKeepsItsEntry() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let codexSaved = UsageInfo(providerID: "codex", providerName: "OpenAI Codex", windows: [], plan: "Pro",
                                   lastUpdated: t0.addingTimeInterval(-7200))
        let store = SnapshotStore(fileURL: dir.appendingPathComponent("s.json"))
        try store.save([saved, codexSaved])
        let items = store.load()
        let service = UsageService(providers: [
            HybridProvider(direct: Live(), relay: SnapshotProvider(id: "claude", displayName: "Claude Code", items: items),
                           isDirectEnabled: { true }),
            HybridProvider(direct: Live(), relay: SnapshotProvider(id: "codex", displayName: "OpenAI Codex", items: items),
                           isDirectEnabled: { false }),
        ], store: store, history: UsageHistoryStore(fileURL: dir.appendingPathComponent("h.json")),
           clock: { t0 }, saveLock: testSaveLock())
        _ = await service.refresh()
        let after = store.load()
        #expect(after.first { $0.providerID == "claude" }?.primary?.usedPercent == 40)
        #expect(after.first { $0.providerID == "codex" } == codexSaved)
    }
}

@Suite struct NotificationStateFileTests {
    @Test func roundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = NotificationStateFile(url: url)
        let state = NotificationState(loginNotified: ["codex"])
        file.save(state)
        #expect(file.load() == state)
    }
}
#endif
