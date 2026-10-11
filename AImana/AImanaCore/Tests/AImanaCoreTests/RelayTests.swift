import Foundation
import Testing
@testable import AImanaCore

private struct DataSource: RelayDataSource {
    var data: Data?
    func readData() async throws -> Data {
        guard let data else { throw UsageProviderError.relayUnavailable }
        return data
    }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func usage(_ id: String, used: Double) -> UsageInfo {
    UsageInfo(providerID: id, providerName: id,
              windows: [UsageWindow(kind: .session, usedPercent: used, windowMinutes: 300, resetsAt: t0.addingTimeInterval(3600))],
              plan: nil, lastUpdated: t0)
}

private func envelopeData(_ entries: [RelayEntry], generatedAt: Date = t0, version: Int = RelayEnvelope.currentVersion) throws -> Data {
    try RelayEnvelope(version: version, generatedAt: generatedAt, entries: entries).encoded()
}

@Suite struct RelayTests {
    @Test func envelopeRoundTrip() throws {
        let env = RelayEnvelope(version: 1, generatedAt: t0, entries: [
            RelayEntry(providerID: "claude", usage: usage("claude", used: 9), error: nil),
            RelayEntry(providerID: "codex", usage: nil, error: .unauthenticated),
        ])
        let decoded = try RelayEnvelope.decode(try env.encoded())
        #expect(decoded == env)
    }

    @Test func providerReturnsItsEntry() async throws {
        let data = try envelopeData([RelayEntry(providerID: "claude", usage: usage("claude", used: 9), error: nil),
                                     RelayEntry(providerID: "codex", usage: usage("codex", used: 16), error: nil)])
        let codex = RelayProvider(id: "codex", displayName: "OpenAI Codex", source: DataSource(data: data))
        let info = try await codex.fetchUsage()
        #expect(info.providerID == "codex")
        #expect(info.primary?.usedPercent == 16)
    }

    @Test func relayErrorCodeIsSurfaced() async throws {
        let data = try envelopeData([RelayEntry(providerID: "claude", usage: nil, error: .unauthenticated)])
        let p = RelayProvider(id: "claude", displayName: "Claude", source: DataSource(data: data))
        await #expect(throws: UsageProviderError.unauthenticated) { try await p.fetchUsage() }
    }

    @Test func missingEntryAndMissingFileAreRelayUnavailable() async throws {
        let data = try envelopeData([RelayEntry(providerID: "claude", usage: usage("claude", used: 1), error: nil)])
        await #expect(throws: UsageProviderError.relayUnavailable) {
            try await RelayProvider(id: "codex", displayName: "x", source: DataSource(data: data)).fetchUsage()
        }
        await #expect(throws: UsageProviderError.relayUnavailable) {
            try await RelayProvider(id: "codex", displayName: "x", source: DataSource(data: nil)).fetchUsage()
        }
    }

    @Test func corruptOrNewerVersionIsDecodingError() async throws {
        await #expect(throws: UsageProviderError.decoding) {
            try await RelayProvider(id: "c", displayName: "c", source: DataSource(data: Data("nope".utf8))).fetchUsage()
        }
        let future = try envelopeData([RelayEntry(providerID: "c", usage: usage("c", used: 1), error: nil)], version: 99)
        await #expect(throws: UsageProviderError.decoding) {
            try await RelayProvider(id: "c", displayName: "c", source: DataSource(data: future)).fetchUsage()
        }
    }

    @Test func staleRelayKeepsOriginalTimestamp() async throws {
        // The Mac stopped publishing 3 h ago: data is shown with its original lastUpdated, never refreshed to "now".
        let data = try envelopeData([RelayEntry(providerID: "claude", usage: usage("claude", used: 9), error: nil)],
                                    generatedAt: t0.addingTimeInterval(-3 * 3600))
        let info = try await RelayProvider(id: "claude", displayName: "Claude", source: DataSource(data: data)).fetchUsage()
        #expect(info.lastUpdated == t0)
    }

    @Test func windowKindWireFormatIsStableText() throws {
        let window = UsageWindow(kind: .model("Fable"), usedPercent: 4, windowMinutes: 10080, resetsAt: nil)
        let json = String(decoding: try JSONEncoder().encode(window), as: UTF8.self)
        #expect(json.contains("\"kind\":\"model:Fable\""))
        #expect(UsageWindow.Kind(wireValue: "session") == .session)
        #expect(UsageWindow.Kind(wireValue: "weekly") == .weekly)
        #expect(UsageWindow.Kind(wireValue: "model:Opus") == .model("Opus"))
        #expect(UsageWindow.Kind(wireValue: "bogus") == nil)
        #expect(UsageWindow.Kind(wireValue: "model:") == nil)
    }

    @Test func errorCodesRoundTrip() {
        for error: UsageProviderError in [.unauthenticated, .decoding, .network, .relayUnavailable] {
            #expect(RelayErrorCode(error).providerError == error)
        }
        #expect(RelayErrorCode(.rateLimited(until: nil)).providerError == .rateLimited(until: nil))
        #expect(RelayErrorCode(.server(status: 503)).providerError == .server(status: 503))
    }
}
