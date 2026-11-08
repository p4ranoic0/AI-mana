import AImanaCore
import CryptoKit
import Foundation
import Testing
@testable import RelayDirect
@testable import RelayKit

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../Fixtures/parity").standardizedFileURL

/// An unsigned JWT whose only claim is `exp`.
private func jwt(exp: Date) -> String {
    let payload = Data(#"{"exp":\#(Int(exp.timeIntervalSince1970))}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJub25lIn0.\(payload)."
}

private func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

private struct Home {
    let root: URL
    init() throws { root = try makeTempDir() }
    func paths(_ environment: [String: String] = [:]) -> RelayPaths {
        RelayPaths(home: root, environment: environment, platform: .macOS)
    }
    func write(_ text: String, to relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    func copyFixture(_ name: String, to relative: String) throws -> URL {
        try write(String(decoding: try Data(contentsOf: fixtures.appendingPathComponent(name)), as: UTF8.self),
                  to: relative)
    }
}

@Suite struct CodexAuthFileTokensTests {
    @Test func readsDefaultHome() async throws {
        let home = try Home()
        _ = try home.copyFixture("codex-auth-file.json", to: ".codex/auth.json")
        let credential = try await CodexAuthFileTokens(paths: home.paths()).credentials()
        #expect(credential.accountID == "acct-fake")
    }

    @Test func codexHonorsCodexHome() async throws {
        let home = try Home()
        _ = try home.copyFixture("codex-auth-file.json", to: "custom-codex/auth.json")
        let paths = home.paths(["CODEX_HOME": home.root.appendingPathComponent("custom-codex").path])
        let credential = try await CodexAuthFileTokens(paths: paths).credentials()
        #expect(credential.accountID == "acct-fake")
    }

    @Test func codexExpiredIsUnauthenticated() async throws {
        let home = try Home()
        _ = try home.write(#"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(jwt(exp: Date(timeIntervalSinceNow: -60)))","account_id":"a"}}"#,
                           to: ".codex/auth.json")
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }

    @Test func codexKeyringIsUnsupported() async throws {
        let home = try Home()
        _ = try home.write("model = \"x\"\ncli_auth_credentials_store = \"keyring\"\n", to: ".codex/config.toml")
        await #expect(throws: UsageProviderError.unsupportedCredentialStore) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }

    @Test func codexKeyringWithInlineCommentIsUnsupported() async throws {
        let home = try Home()
        _ = try home.write("cli_auth_credentials_store = \"auto\"   # keep it in the OS keyring\n", to: ".codex/config.toml")
        await #expect(throws: UsageProviderError.unsupportedCredentialStore) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }

    @Test func codexFileStoreStaysSignedOut() async throws {
        let home = try Home()
        _ = try home.write("cli_auth_credentials_store = 'file' # default\n", to: ".codex/config.toml")
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }

    @Test func codexApiKeyModeIsUnauthenticated() async throws {
        let home = try Home()
        _ = try home.write(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-fake"}"#, to: ".codex/auth.json")
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }

    @Test func codexMissingIsUnauthenticated() async throws {
        let home = try Home()
        await #expect(throws: UsageProviderError.unauthenticated) {
            try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
    }
}

@Suite struct ClaudeCLITokensTests {
    @Test func keychainWinsOverFile() async throws {
        let home = try Home()
        _ = try home.copyFixture("claude-credentials-file.json", to: ".claude/.credentials.json")
        let tokens = ClaudeCLITokens(paths: home.paths(), keychain: {
            ["accessToken": "from-keychain", "expiresAt": 4_102_444_800_000.0, "subscriptionType": "pro"]
        })
        let credential = try await tokens.credentials()
        #expect(credential.token == "from-keychain")
        #expect(credential.plan == "pro")
    }

    @Test func claudeFileFallbackReadsOnlyClaudeBlock() async throws {
        let home = try Home()
        _ = try home.copyFixture("claude-credentials-file.json", to: ".claude/.credentials.json")
        let credential = try await ClaudeCLITokens(paths: home.paths(), keychain: { nil }).credentials()
        #expect(credential == AccessCredential(token: "fake-claude-access", plan: "max"))
        let oauth = try #require(ClaudeCredentialsFile.readOAuth(paths: home.paths()))
        #expect(Set(oauth.keys).isDisjoint(with: ["mcpOAuth", "serverUrl", "clientSecret"]))
    }

    @Test func claudeFileHonorsConfigDir() async throws {
        let home = try Home()
        _ = try home.copyFixture("claude-credentials-file.json", to: "alt-claude/.credentials.json")
        let paths = home.paths(["CLAUDE_CONFIG_DIR": home.root.appendingPathComponent("alt-claude").path])
        let credential = try await ClaudeCLITokens(paths: paths, keychain: { nil }).credentials()
        #expect(credential.token == "fake-claude-access")
    }

    @Test func claudeExpiredWithoutRenewIsUnauthenticated() async throws {
        let home = try Home()
        let tokens = ClaudeCLITokens(paths: home.paths(), keychain: {
            ["accessToken": "old", "expiresAt": Date(timeIntervalSinceNow: -60).timeIntervalSince1970 * 1000]
        })
        await #expect(throws: UsageProviderError.unauthenticated) { try await tokens.credentials() }
    }

    @Test func renewalRunsTheClaudeCLIAndPicksUpTheNewSession() async throws {
        let home = try Home()
        let marker = home.root.appendingPathComponent("cli-ran")
        // The fake CLI writes a renewed session where the reader looks, like Claude Code rewrites its own entry.
        let renewed = #"{"claudeAiOauth":{"accessToken":"renewed","expiresAt":4102444800000,"subscriptionType":"max"}}"#
        let script = try home.write("""
            #!/bin/sh
            touch '\(marker.path)'
            printf '%s' '\(renewed)' > '\(home.root.path)/.claude/.credentials.json'
            """, to: "bin/claude")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        _ = try home.write(#"{"claudeAiOauth":{"accessToken":"old","expiresAt":\#(Date(timeIntervalSinceNow: -60).timeIntervalSince1970 * 1000)}}"#,
                           to: ".claude/.credentials.json")
        let paths = home.paths(["CLAUDE_BIN": script.path])
        let credential = try await ClaudeCLITokens(renew: true, paths: paths, keychain: { nil }).credentials()
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(credential.token == "renewed")
    }

    @Test func readersNeverWrite() async throws {
        let home = try Home()
        let claude = try home.copyFixture("claude-credentials-file.json", to: ".claude/.credentials.json")
        let codex = try home.copyFixture("codex-auth-file.json", to: ".codex/auth.json")
        let before = (try sha256(claude), try sha256(codex))
        for _ in 0..<3 {
            _ = try await ClaudeCLITokens(paths: home.paths(), keychain: { nil }).credentials()
            _ = try await CodexAuthFileTokens(paths: home.paths()).credentials()
        }
        #expect(try sha256(claude) == before.0)
        #expect(try sha256(codex) == before.1)
    }
}
