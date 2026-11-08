import AImanaCore
import Foundation

/// OpenAI Codex usage via `GET chatgpt.com/backend-api/wham/usage` (unofficial; see Docs/UsageEndpoints.md).
public struct CodexProvider: UsageProvider {
    public let id = "codex"
    public let displayName = "OpenAI Codex"

    private static let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
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

        var request = URLRequest(url: Self.url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AImana", forHTTPHeaderField: "User-Agent")
        if let account = credential.accountID, !account.isEmpty {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network
        }

        switch response.statusCode {
        case 200:
            return try Self.map(data, now: now)
        case 401, 403:
            throw UsageProviderError.unauthenticated
        case 429:
            let until = RetryAfter.date(from: response, now: now)
            await gate.block(until: until)
            throw UsageProviderError.rateLimited(until: until)
        default:
            throw UsageProviderError.server(status: response.statusCode)
        }
    }

    // MARK: Mapping (pure, unit-tested)

    private struct Window: Decodable {
        let used_percent: Double
        let reset_at: Double
        let limit_window_seconds: Double
    }

    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    /// `balance` arrives as a number or a numeric string.
    private struct Credits: Decodable {
        let has_credits: Bool?
        let unlimited: Bool?
        let balance: Double?

        enum CodingKeys: String, CodingKey { case has_credits, unlimited, balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            has_credits = try? c.decode(Bool.self, forKey: .has_credits)
            unlimited = try? c.decode(Bool.self, forKey: .unlimited)
            if let number = try? c.decode(Double.self, forKey: .balance) {
                balance = number
            } else if let text = try? c.decode(String.self, forKey: .balance) {
                balance = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                balance = nil
            }
        }
    }

    private struct ResetCredits: Decodable {
        let available_count: Int?
        let applicable_available_count: Int?
    }

    /// Model-specific limits next to the main ones (openai/codex `AdditionalRateLimitDetails`):
    /// `{limit_name, metered_feature, rate_limit: {primary_window, secondary_window}}`.
    private struct AdditionalLimit: Decodable {
        let limit_name: String?
        let metered_feature: String?
        let rate_limit: RateLimit?
    }

    private struct Response: Decodable {
        let plan_type: String?
        let rate_limit: RateLimit?
        let additional_rate_limits: Lossy<[Lossy<AdditionalLimit>]>?
        let credits: Lossy<Credits>?
        let rate_limit_reset_credits: Lossy<ResetCredits>?
    }

    static func map(_ data: Data, now: Date) throws -> UsageInfo {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let limit = response.rate_limit,
              limit.primary_window != nil || limit.secondary_window != nil else {
            throw UsageProviderError.decoding
        }
        func build(_ raw: Window?) -> (minutes: Int, used: Double, reset: Date)? {
            guard let raw, raw.used_percent.isFinite, raw.reset_at.isFinite, raw.limit_window_seconds.isFinite else { return nil }
            return (Int(raw.limit_window_seconds / 60), raw.used_percent, Date(timeIntervalSince1970: raw.reset_at))
        }
        // The API does not guarantee which slot holds which lane: classify by duration (300 = session, 10080 = weekly).
        var session: UsageWindow?
        var weekly: UsageWindow?
        var unknown: [(minutes: Int, used: Double, reset: Date)] = []
        for slot in [build(limit.primary_window), build(limit.secondary_window)].compactMap({ $0 }) {
            switch slot.minutes {
            case 300: session = UsageWindow(kind: .session, usedPercent: slot.used, windowMinutes: 300, resetsAt: slot.reset)
            case 10080: weekly = UsageWindow(kind: .weekly, usedPercent: slot.used, windowMinutes: 10080, resetsAt: slot.reset)
            default: unknown.append(slot)
            }
        }
        // Unrecognised durations keep CodexBar's slot semantics: first fills session, then weekly.
        for slot in unknown {
            if session == nil {
                session = UsageWindow(kind: .session, usedPercent: slot.used, windowMinutes: slot.minutes, resetsAt: slot.reset)
            } else if weekly == nil {
                weekly = UsageWindow(kind: .weekly, usedPercent: slot.used, windowMinutes: slot.minutes, resetsAt: slot.reset)
            }
        }
        var windows = [session, weekly].compactMap { $0 }
        guard !windows.isEmpty else { throw UsageProviderError.decoding }
        windows += additionalWindows(response.additional_rate_limits?.value?.compactMap(\.value) ?? [])
        var details: [UsageDetail] = []
        if let resets = response.rate_limit_reset_credits?.value, let count = resets.available_count, count > 0 {
            details.append(UsageDetail(kind: .resetCredits, remaining: Double(count),
                                       usable: resets.applicable_available_count.map(Double.init)))
        }
        if let credits = response.credits?.value, credits.has_credits == true, credits.unlimited != true,
           let balance = credits.balance, balance.isFinite, balance > 0 {
            details.append(UsageDetail(kind: .creditBalance, remaining: balance, currency: "USD"))
        }
        return UsageInfo(providerID: "codex", providerName: "OpenAI Codex",
                         windows: windows, plan: response.plan_type, lastUpdated: now, details: details)
    }

    /// Extra lanes per additional limit, named after it: windows shorter than a day become `.modelSession`,
    /// longer ones `.model`. They never replace the main session/weekly lanes. Malformed entries are skipped.
    private static func additionalWindows(_ limits: [AdditionalLimit]) -> [UsageWindow] {
        var result: [UsageWindow] = []
        for limit in limits {
            let rawName = limit.limit_name ?? limit.metered_feature ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let rate = limit.rate_limit else { continue }
            for raw in [rate.primary_window, rate.secondary_window].compactMap({ $0 }) {
                guard raw.used_percent.isFinite, raw.reset_at.isFinite, raw.limit_window_seconds.isFinite,
                      raw.limit_window_seconds > 0 else { continue }
                let minutes = Int(raw.limit_window_seconds / 60)
                let kind: UsageWindow.Kind = minutes < 1440 ? .modelSession(name) : .model(name)
                guard !result.contains(where: { $0.kind == kind }) else { continue }
                result.append(UsageWindow(kind: kind, usedPercent: raw.used_percent, windowMinutes: minutes,
                                          resetsAt: raw.reset_at > 0 ? Date(timeIntervalSince1970: raw.reset_at) : nil))
            }
        }
        return result
    }
}
