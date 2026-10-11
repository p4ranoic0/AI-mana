import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension CredentialKey {
    /// The user's own OpenRouter API key (`sk-or-v1-…`), pasted in Settings.
    static let openRouterAPIKey = "openrouter.apiKey"
}

/// OpenRouter usage through its official, documented API with the user's own API key:
/// - `GET /api/v1/key` (any key): spend and credit limit of this key, plus the daily free-model request allowance.
///   https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key
/// - `GET /api/v1/credits` (management keys only): account credits bought and used. Best effort; a regular key
///   gets 401/403 there, which is remembered so it is not asked again.
///   https://openrouter.ai/docs/api/api-reference/credits/get-credits
///
/// Limits reset at midnight UTC; weeks start on Monday (https://openrouter.ai/docs/api/reference/limits).
public struct OpenRouterProvider: UsageProvider {
    public static let providerID = "openrouter"
    public static let name = "OpenRouter"
    public let id = OpenRouterProvider.providerID
    public let displayName = OpenRouterProvider.name

    static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!
    static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    private let transport: any HTTPTransport
    private let tokens: any AccessTokenSource
    private let enabled: @Sendable () -> Bool
    private let clock: @Sendable () -> Date
    private let gate = BackoffGate()
    private let creditsAccess = CreditsAccess()

    /// - Parameter isEnabled: whether a key is saved; the provider stays out of the dashboard until then.
    public init(transport: any HTTPTransport = URLSessionTransport(),
                tokens: any AccessTokenSource,
                isEnabled: @escaping @Sendable () -> Bool = { true },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.tokens = tokens
        self.enabled = isEnabled
        self.clock = clock
    }

    /// Reads the key from `store` (the shared Keychain in the app and the widget) and is enabled only while one is saved.
    public init(store: any CredentialStore, transport: any HTTPTransport = URLSessionTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(transport: transport,
                  tokens: StoredTokenSource(store: store, tokenKey: CredentialKey.openRouterAPIKey),
                  isEnabled: { Self.hasKey(in: store) },
                  clock: clock)
    }

    public var isEnabled: Bool { enabled() }

    public static func hasKey(in store: any CredentialStore) -> Bool {
        guard let key = try? store.read(CredentialKey.openRouterAPIKey) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checks a pasted key with one `GET /key` before it is saved. Throws `.unauthenticated` for a rejected key.
    public static func validate(key: String, transport: any HTTPTransport = URLSessionTransport()) async throws -> UsageInfo {
        try await OpenRouterProvider(transport: transport, tokens: FixedKey(key: key)).fetchUsage()
    }

    public func fetchUsage() async throws -> UsageInfo {
        let now = clock()
        if let until = await gate.check(now: now) { throw UsageProviderError.rateLimited(until: until) }
        let token = try await tokens.credentials().token

        let (data, response) = try await get(Self.keyURL, token: token)
        switch response.statusCode {
        case 200:
            let credits = await fetchCredits(token: token)
            return try Self.map(key: data, credits: credits, now: now)
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

    /// `nil` when the key may not read account credits or the call fails; never fails the whole reading.
    private func fetchCredits(token: String) async -> Data? {
        guard await creditsAccess.isAllowed(for: token) else { return nil }
        guard let (data, response) = try? await get(Self.creditsURL, token: token) else { return nil }
        switch response.statusCode {
        case 200: return data
        case 401, 403: await creditsAccess.deny(token); return nil
        default: return nil
        }
    }

    private func get(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AImana", forHTTPHeaderField: "User-Agent")
        do {
            return try await transport.send(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network
        }
    }

    // MARK: Mapping (pure, unit-tested)

    private struct FreeRequests: Decodable {
        let used: Double?
        let limit: Double?
        let remaining: Double?
    }

    private struct KeyData: Decodable {
        let limit: Lossy<Double>?
        let limit_remaining: Lossy<Double>?
        let limit_reset: Lossy<String>?
        let usage: Lossy<Double>?
        let usage_daily: Lossy<Double>?
        let usage_weekly: Lossy<Double>?
        let usage_monthly: Lossy<Double>?
        let is_free_tier: Lossy<Bool>?
        let free_model_daily_requests: Lossy<FreeRequests>?
    }

    private struct KeyResponse: Decodable { let data: KeyData }

    private struct CreditsData: Decodable {
        let total_credits: Double
        let total_usage: Double
    }

    private struct CreditsResponse: Decodable { let data: CreditsData }

    static func map(key: Data, credits: Data?, now: Date) throws -> UsageInfo {
        guard let response = try? JSONDecoder().decode(KeyResponse.self, from: key) else {
            throw UsageProviderError.decoding
        }
        let info = response.data
        func finite(_ value: Lossy<Double>?) -> Double? {
            guard let value = value?.value, value.isFinite else { return nil }
            return value
        }
        var windows: [UsageWindow] = []

        // Credit limit of this key: share spent in the current reset period (or ever, when it never resets).
        if let limit = finite(info.limit), limit > 0 {
            let reset = info.limit_reset?.value.flatMap(ResetPeriod.init(rawValue:))
            let periodUsage: Double? = switch reset {
            case .daily: finite(info.usage_daily)
            case .weekly: finite(info.usage_weekly)
            case .monthly: finite(info.usage_monthly)
            case nil: finite(info.usage)
            }
            let spent = finite(info.limit_remaining).map { limit - $0 } ?? periodUsage
            if let spent {
                let period = reset.map { $0.period(containing: now) }
                windows.append(UsageWindow(kind: .spendLimit, usedPercent: max(0, spent) / limit * 100,
                                           windowMinutes: period.map { Int($0.end.timeIntervalSince($0.start) / 60) },
                                           resetsAt: period?.end))
            }
        }

        // Free-model requests per UTC day. Only worth a lane when they matter: free tier, used today, or nothing else.
        let isFreeTier = info.is_free_tier?.value ?? false
        if let free = info.free_model_daily_requests?.value, let limit = free.limit, limit.isFinite, limit > 0 {
            // Neither `used` nor `remaining`: no reading, so no lane (never a made-up 0 %).
            if let used = free.used ?? free.remaining.map({ limit - $0 }),
               used.isFinite, isFreeTier || used > 0 || windows.isEmpty {
                let day = ResetPeriod.daily.period(containing: now)
                windows.append(UsageWindow(kind: .freeRequests, usedPercent: max(0, used) / limit * 100,
                                           windowMinutes: 1440, resetsAt: day.end))
            }
        }

        var details: [UsageDetail] = []
        if let credits, let account = try? JSONDecoder().decode(CreditsResponse.self, from: credits).data,
           account.total_credits.isFinite, account.total_usage.isFinite {
            details.append(UsageDetail(kind: .creditBalance, remaining: account.total_credits - account.total_usage,
                                       limit: account.total_credits, currency: "USD", used: account.total_usage))
        }
        if let monthly = finite(info.usage_monthly) {
            details.append(UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: monthly))
        }

        return UsageInfo(providerID: providerID, providerName: name, windows: windows,
                         plan: isFreeTier ? "Free" : nil, lastUpdated: now, details: details)
    }

    /// `limit_reset` values. Periods are UTC; weeks run Monday to Sunday.
    enum ResetPeriod: String {
        case daily, weekly, monthly

        func period(containing date: Date) -> (start: Date, end: Date) {
            var calendar = Calendar(identifier: .iso8601)   // weeks start on Monday
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let component: Calendar.Component = switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            }
            guard let interval = calendar.dateInterval(of: component, for: date) else {
                return (date, date.addingTimeInterval(86400))
            }
            return (interval.start, interval.end)
        }
    }
}

/// A key typed in Settings, before it is saved.
struct FixedKey: AccessTokenSource {
    let key: String
    func credentials() async throws -> AccessCredential {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UsageProviderError.unauthenticated }
        return AccessCredential(token: trimmed)
    }
}

/// Remembers which key may not read `/credits`, so later refreshes skip that request. Tied to the key: replacing
/// an ordinary key with a management key while the app runs must try `/credits` again.
private actor CreditsAccess {
    private var deniedKey: String?
    func isAllowed(for key: String) -> Bool { key != deniedKey }
    func deny(_ key: String) { deniedKey = key }
}
