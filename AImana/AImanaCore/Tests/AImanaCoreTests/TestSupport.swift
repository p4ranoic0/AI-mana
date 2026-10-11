import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AImanaCore

// MARK: - Test doubles

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int; var body: String; var headers: [String: String] = [:] }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = lock.withLock { () -> Reply in
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "") : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: nil, headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

struct FixedTokens: AccessTokenSource {
    var credential: AccessCredential? = AccessCredential(token: "tok", accountID: "acct")
    func credentials() async throws -> AccessCredential {
        guard let credential else { throw UsageProviderError.unauthenticated }
        return credential
    }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)

