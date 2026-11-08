import Foundation
import Testing
@testable import AImanaCore

@Suite struct RelayErrorCodeWireTests {
    @Test func keyringErrorStaysPreciseInMemory() {
        #expect(RelayErrorCode(UsageProviderError.unsupportedCredentialStore) == .unsupportedCredentialStore)
        #expect(RelayErrorCode.unsupportedCredentialStore.providerError == .unsupportedCredentialStore)
    }

    @Test func keyringErrorTravelsAsUnauthenticatedForOlderPhones() throws {
        let entry = RelayEntry(providerID: "codex", usage: nil, error: .unsupportedCredentialStore)
        let json = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(json.contains(#""error":"unauthenticated""#))
        #expect(!json.contains("unsupportedCredentialStore"))
        let decoded = try JSONDecoder().decode(RelayEntry.self, from: Data(json.utf8))
        #expect(decoded.error == .unauthenticated)
    }
}
