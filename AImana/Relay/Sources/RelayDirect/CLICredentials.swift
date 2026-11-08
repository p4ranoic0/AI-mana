import RelayKit
import AImanaCore
import Foundation

/// Reads the credentials the official CLIs already keep on this computer. Nothing is copied or written: each run
/// re-reads the source, so tokens the CLIs rotate are picked up, and expired tokens are never sent.

public struct CodexAuthFileTokens: AccessTokenSource {
    let paths: RelayPaths

    public init(paths: RelayPaths = .standard) { self.paths = paths }

    public func credentials() async throws -> AccessCredential {
        let authFile = paths.codexHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authFile) else {
            // No file: either signed out, or the CLI keeps its session in the system keyring, which is not a sign-out.
            throw Self.keepsSessionOutsideFile(paths) ? UsageProviderError.unsupportedCredentialStore
                                                       : UsageProviderError.unauthenticated
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.unauthenticated
        }
        // An API-key login has no subscription quota to read.
        if let mode = json["auth_mode"] as? String, mode != "chatgpt" { throw UsageProviderError.unauthenticated }
        guard let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else {
            throw UsageProviderError.unauthenticated
        }
        if let exp = Self.jwtExpiry(access), exp <= Date() { throw UsageProviderError.unauthenticated }
        return AccessCredential(token: access, accountID: tokens["account_id"] as? String)
    }

    /// `cli_auth_credentials_store = "keyring"` (or `"auto"`) in `config.toml`.
    static func keepsSessionOutsideFile(_ paths: RelayPaths) -> Bool {
        guard let text = try? String(contentsOf: paths.codexHome.appendingPathComponent("config.toml"),
                                     encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { line in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "cli_auth_credentials_store" else { return false }
            // A TOML string, optionally followed by a `# comment`.
            let raw = parts[1]
            let value: Substring
            if let quote = raw.first, quote == "\"" || quote == "'" {
                value = raw.dropFirst().prefix { $0 != quote }
            } else {
                value = raw.prefix { $0 != "#" }
            }
            let store = value.trimmingCharacters(in: .whitespaces)
            return store == "keyring" || store == "auto"
        }
    }

    static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

/// Reads Claude Code's OAuth entry from the login Keychain via /usr/bin/security.
public enum ClaudeKeychain {
    public static func readOAuth() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: out.fileHandleForReading.readDataToEndOfFile()) as? [String: Any]
        else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }

    public static func expiry(_ oauth: [String: Any]?) -> Date? {
        (oauth?["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Claude Code's sign-in file (`.credentials.json`), used where there is no Keychain item. The file also holds other
/// tools' secrets (e.g. `mcpOAuth`): only the `claudeAiOauth` block is returned, and nothing else is kept.
public enum ClaudeCredentialsFile {
    public static func readOAuth(paths: RelayPaths) -> [String: Any]? {
        let url = paths.claudeConfigDirectory.appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["claudeAiOauth"] as? [String: Any]
    }
}

/// Asks the Claude CLI to renew its own session. The CLI owns the credential and rewrites its Keychain entry or file;
/// the relay never reads, copies or writes a refresh token, and only observes whether the expiry moved.
/// `claude auth status` makes no model call, so it costs no quota.
public enum ClaudeRenewer {
    public enum Outcome: CustomStringConvertible {
        case renewed, unchanged, failed(String)
        public var description: String {
            switch self {
            case .renewed: "renewed"
            case .unchanged: "CLI ran but the session did not change"
            case .failed(let why): "failed: \(why)"
            }
        }
    }

    private static func stateURL(_ paths: RelayPaths) -> URL { paths.caches.appendingPathComponent("claude-renew.json") }

    static func lastAttempt(paths: RelayPaths = .standard) -> Date? {
        guard let data = try? Data(contentsOf: stateURL(paths)),
              let seconds = (try? JSONSerialization.jsonObject(with: data) as? [String: Double])?["lastAttempt"] else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func recordAttempt(_ date: Date, paths: RelayPaths) {
        RelayPaths.ensure(paths.caches)
        let data = try? JSONSerialization.data(withJSONObject: ["lastAttempt": date.timeIntervalSince1970])
        try? data?.write(to: stateURL(paths), options: .atomic)
    }

    /// Never resolves `claude` through PATH: a terminal wrapper (e.g. a shim) may sit first there.
    static func binary(paths: RelayPaths = .standard) -> URL? {
        let home = paths.home.path
        let candidates = [paths.environment["CLAUDE_BIN"], "\(home)/.local/bin/claude", "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude", "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public static func attempt(paths: RelayPaths = .standard, now: Date = Date(), timeout: TimeInterval = 30,
                               read: @escaping @Sendable () -> [String: Any]? = { ClaudeKeychain.readOAuth() }) async -> Outcome {
        guard let binary = binary(paths: paths) else { return .failed("claude CLI not found") }
        recordAttempt(now, paths: paths)
        let before = ClaudeKeychain.expiry(read())

        let process = Process()
        process.executableURL = binary
        process.arguments = ["auth", "status", "--json"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["\(paths.home.path)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            .joined(separator: ":")
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        // The output contains the account email: discard it, never log it.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed("could not start CLI") }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        if process.isRunning {
            process.terminate()
            return .failed("CLI timed out after \(Int(timeout))s")
        }
        guard process.terminationStatus == 0 else { return .failed("CLI exited with status \(process.terminationStatus)") }

        // The CLI may write its entry slightly after it exits.
        for _ in 0..<20 {
            if let after = ClaudeKeychain.expiry(read()), after > (before ?? .distantPast) { return .renewed }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return .unchanged
    }
}

/// Claude Code's session on this computer: the Keychain item first, then `.credentials.json`.
public struct ClaudeCLITokens: AccessTokenSource {
    /// When true, an expired or about-to-expire session triggers one (rate-limited) renewal attempt via the CLI.
    let renew: Bool
    let paths: RelayPaths
    let keychain: @Sendable () -> [String: Any]?
    let log: @Sendable (String) -> Void

    public init(renew: Bool = false, paths: RelayPaths = .standard,
                keychain: @escaping @Sendable () -> [String: Any]? = { ClaudeKeychain.readOAuth() },
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.renew = renew
        self.paths = paths
        self.keychain = keychain
        self.log = log
    }

    func read() -> [String: Any]? { keychain() ?? ClaudeCredentialsFile.readOAuth(paths: paths) }

    public func credentials() async throws -> AccessCredential {
        var oauth = read()
        guard oauth != nil else { throw UsageProviderError.unauthenticated }

        if renew, RenewalPolicy.shouldAttempt(expiresAt: ClaudeKeychain.expiry(oauth),
                                              lastAttempt: ClaudeRenewer.lastAttempt(paths: paths), now: Date()) {
            log("claude: session expiring, asking the Claude CLI to renew it")
            let outcome = await ClaudeRenewer.attempt(paths: paths, read: { [self] in read() })
            log("claude: renewal \(outcome)")
            oauth = read()
        }

        guard let oauth, let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw UsageProviderError.unauthenticated
        }
        if let expiry = ClaudeKeychain.expiry(oauth), expiry <= Date() {
            // Still expired: report "sign in needed" instead of sending a dead token.
            throw UsageProviderError.unauthenticated
        }
        return AccessCredential(token: token, plan: oauth["subscriptionType"] as? String)
    }
}
