import Foundation
import Testing
@testable import AImanaCore

struct RelaySourceTests {
    private let base = #"{"version":1,"generatedAt":"2026-10-06T10:00:00Z","entries":[{"providerID":"claude"%@}]}"#

    private func decode(_ extra: String) throws -> RelayEntry {
        try #require(RelayEnvelope.decode(Data(String(format: base, extra).utf8)).entries.first)
    }

    @Test func olderFilesWithoutSourceStillDecode() throws {
        #expect(try decode("").source == nil)
    }

    @Test func knownSourceRoundTrips() throws {
        #expect(try decode(#","source":"statusline""#).source == .statusline)
        let envelope = RelayEnvelope(generatedAt: Date(timeIntervalSince1970: 0),
                                     entries: [RelayEntry(providerID: "codex", usage: nil, error: nil, source: .logs)])
        #expect(try RelayEnvelope.decode(envelope.encoded()).entries.first?.source == .logs)
    }

    @Test func unknownSourceFromNewerMacDecodesAsNil() throws {
        #expect(try decode(#","source":"carrier-pigeon""#).source == nil)
    }
}
