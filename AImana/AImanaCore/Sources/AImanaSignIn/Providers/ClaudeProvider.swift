import AImanaCore
import Foundation

/// Claude Code usage via `GET api.anthropic.com/api/oauth/usage` (unofficial; see Docs/UsageEndpoints.md).
public struct ClaudeProvider: UsageProvider {
    public let id = "claude"
    public let displayName = "Claude Code"

    private static let base = "https://api.anthropic.com/api/oauth/usage"
    private let transport: any HTTPTransport
    private let tokens: any AccessTokenSource
    private let clock: @Sendable () -> Date
    private let gate: BackoffGate

    public init(transport: any HTTPTransport = URLSessionTransport(),
                tokens: any AccessTokenSource,
                clock: @escaping @Sendable () -> Date = { Date() },
                gate: BackoffGate = BackoffGate()) {
        self.transport = transport
        self.tokens = tokens
        self.clock = clock
        self.gate = gate
    }

    public func fetchUsage() async throws -> UsageInfo {
        let now = clock()
        if let until = await gate.check(now: now) { throw UsageProviderError.rateLimited(until: until) }
        let credential = try await tokens.credentials()

        var (data, response) = try await send(credential, optionalQuery: true)
        // Optional query rejected: retry once without it, same credential.
        if response.statusCode == 400 || (response.statusCode == 403 && !Self.mentionsProfileScope(data)) {
            (data, response) = try await send(credential, optionalQuery: false)
        }

        switch response.statusCode {
        case 200:
            return try Self.map(data, now: now, plan: credential.plan)
        case 401:
            throw UsageProviderError.unauthenticated
        case 403:
            throw UsageProviderError.unauthenticated   // missing user:profile scope
        case 429:
            let until = RetryAfter.date(from: response, now: now)
            await gate.block(until: until)
            throw UsageProviderError.rateLimited(until: until)
        default:
            throw UsageProviderError.server(status: response.statusCode)
        }
    }

    private func send(_ credential: AccessCredential, optionalQuery: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: Self.base + (optionalQuery ? "?cedar_ember=1" : ""))!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/2.1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        do {
            return try await transport.send(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network
        }
    }

    private static func mentionsProfileScope(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains("user:profile") ?? false
    }

    // MARK: Mapping (pure, unit-tested)

    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    /// Newer `limits[]` shape: entries scoped to one model carry `scope.model.display_name`.
    private struct LimitEntry: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable { let display_name: String? }
            let model: Model?
        }
        let percent: Double?
        let resets_at: String?
        let scope: Scope?
    }

    /// Promotional cloud credit; the API reports dollars (not minor units).
    private struct CloudCredits: Decodable {
        let limit_dollars: Double
        let used_dollars: Double?
        let remaining_dollars: Double?
        let resets_at: String?
        let locked_reason: String?
    }

    /// Paid usage beyond the plan. Amounts are in cents (CodexBar: "OAuth extra usage is always in cents");
    /// `utilization` is 0...100. The claude.ai web API spells the cap `monthly_credit_limit`.
    private struct ExtraUsage: Decodable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let monthly_credit_limit: Double?
        let used_credits: Double?
        let utilization: Double?
        let currency: String?
    }

    private struct Response: Decodable {
        let iguana_necktie: Lossy<CloudCredits>?
        let extra_usage: Lossy<ExtraUsage>?
        let limits: [LimitEntry]?
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_sonnet: Window?
        let seven_day_opus: Window?
    }

    /// Mirrors CodexBar's validation: a positive allowance and a balance inside it; locked or expired grants are hidden.
    private static func cloudCredits(_ raw: CloudCredits, now: Date) -> UsageDetail? {
        let limit = raw.limit_dollars
        guard limit.isFinite, limit > 0 else { return nil }
        if let used = raw.used_dollars, !(used.isFinite && used >= 0 && used <= limit) { return nil }
        if let left = raw.remaining_dollars, !(left.isFinite && left >= 0 && left <= limit) { return nil }
        guard let remaining = raw.remaining_dollars ?? raw.used_dollars.map({ limit - $0 }) else { return nil }
        if let reason = raw.locked_reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let expires = ISODate.parse(raw.resets_at)
        if let expires, expires <= now { return nil }
        return UsageDetail(kind: .cloudCredits, remaining: remaining, limit: limit, currency: "USD", expiresAt: expires)
    }

    /// Shown only while enabled; a cap of 0 or a missing cap means "no cap", not "nothing left".
    private static func extraUsage(_ raw: ExtraUsage) -> UsageDetail? {
        guard raw.is_enabled == true else { return nil }
        let cap = (raw.monthly_limit ?? raw.monthly_credit_limit).flatMap { $0.isFinite && $0 > 0 ? $0 / 100 : nil }
        var used = raw.used_credits.flatMap { $0.isFinite && $0 >= 0 ? $0 / 100 : nil }
        if used == nil, let cap, let percent = raw.utilization, percent.isFinite, percent >= 0 {
            used = cap * percent / 100
        }
        guard let used else { return nil }
        let currency = raw.currency.flatMap { $0.count == 3 ? $0.uppercased() : nil } ?? "USD"
        return UsageDetail(kind: .extraUsage, remaining: cap.map { max(0, $0 - used) } ?? 0, limit: cap,
                           currency: currency, used: used)
    }

    static func map(_ data: Data, now: Date, plan: String? = nil) throws -> UsageInfo {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw UsageProviderError.decoding
        }
        func window(_ raw: Window?, _ kind: UsageWindow.Kind, minutes: Int) -> UsageWindow? {
            guard let raw, let used = raw.utilization, used.isFinite else { return nil }
            return UsageWindow(kind: kind, usedPercent: used, windowMinutes: minutes,
                               resetsAt: ISODate.parse(raw.resets_at))
        }
        var windows = [
            window(response.five_hour, .session, minutes: 300),
            window(response.seven_day, .weekly, minutes: 10080),
            window(response.seven_day_sonnet, .model("Sonnet"), minutes: 10080),
            window(response.seven_day_opus, .model("Opus"), minutes: 10080),
        ].compactMap { $0 }
        // Model-scoped weekly limits from `limits[]`, without duplicating lanes already mapped above.
        for entry in response.limits ?? [] {
            guard let name = entry.scope?.model?.display_name, !name.isEmpty,
                  let percent = entry.percent, percent.isFinite,
                  !windows.contains(where: { $0.kind == .model(name) }) else { continue }
            windows.append(UsageWindow(kind: .model(name), usedPercent: percent, windowMinutes: 10080,
                                       resetsAt: ISODate.parse(entry.resets_at)))
        }
        var details: [UsageDetail] = []
        if let credits = response.iguana_necktie?.value, let detail = Self.cloudCredits(credits, now: now) {
            details.append(detail)
        }
        if let extra = response.extra_usage?.value, let detail = Self.extraUsage(extra) {
            details.append(detail)
        }
        // Spend-only accounts (no rate-limit windows) still have something to show when extra usage is on.
        guard !windows.isEmpty || details.contains(where: { $0.kind == .extraUsage }) else {
            throw UsageProviderError.decoding
        }
        return UsageInfo(providerID: "claude", providerName: "Claude Code",
                         windows: windows, plan: plan, lastUpdated: now, details: details)
    }
}

enum ISODate {
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
