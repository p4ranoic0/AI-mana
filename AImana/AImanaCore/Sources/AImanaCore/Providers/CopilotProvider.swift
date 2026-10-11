import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension CredentialKey {
    /// The user's own GitHub personal access token, pasted in Settings, used only for the billing usage report.
    static let gitHubCopilotToken = "copilot.githubToken"
}

/// The Copilot plan the user says they have. GitHub's billing API reports spend but not the included allowance,
/// so the allowance comes from the plan tables in GitHub's docs (or a custom amount).
///
/// AI credits (1 credit = US$0.01), base plus flex allotment, per month:
/// - Pro 1,500 · Pro+ 7,000 · Max 20,000
///   https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals
/// - Business 1,900 and Enterprise 3,900 per user (pooled across the organization or enterprise)
///   https://docs.github.com/en/copilot/get-started/plans
///
/// Legacy premium requests (annual Pro / Pro+ plans that stayed on request billing after 2026-06-01):
/// Pro 300, Pro+ 1,500 per month.
///   https://docs.github.com/en/copilot/concepts/billing/copilot-requests
public enum CopilotPlan: String, CaseIterable, Sendable, Identifiable {
    case pro
    case proPlus = "pro-plus"
    case max
    case business
    case enterprise
    case custom

    public var id: String { rawValue }

    /// AI credits included each month; nil for `.custom`.
    public var includedCredits: Double? {
        switch self {
        case .pro: 1_500
        case .proPlus: 7_000
        case .max: 20_000
        case .business: 1_900
        case .enterprise: 3_900
        case .custom: nil
        }
    }

    /// Premium requests included each month on legacy request billing; documented only for Pro and Pro+.
    public var legacyPremiumRequests: Double? {
        switch self {
        case .pro: 300
        case .proPlus: 1_500
        default: nil
        }
    }

    /// Short name for the plan badge ("Pro+"); nil for a custom amount.
    public var badge: String? {
        switch self {
        case .pro: "Pro"
        case .proPlus: "Pro+"
        case .max: "Max"
        case .business: "Business"
        case .enterprise: "Enterprise"
        case .custom: nil
        }
    }

    /// Picker title: product names stay in English; only "Custom amount" is translated.
    public func title(locale: Locale? = nil) -> String {
        badge.map { "Copilot \($0)" } ?? CoreStrings.text("Custom amount", locale: locale)
    }
}

/// What a reading is measured against: the chosen plan, and for `.custom` the monthly amount in US dollars.
public struct CopilotAllowance: Sendable, Equatable {
    public var plan: CopilotPlan
    public var customUSD: Double?

    public init(plan: CopilotPlan, customUSD: Double? = nil) {
        self.plan = plan
        self.customUSD = customUSD
    }

    /// Included AI credits in US dollars (1 credit = US$0.01). Nil when there is no usable amount.
    public var includedUSD: Double? {
        if let credits = plan.includedCredits { return credits / 100 }
        guard let customUSD, customUSD.isFinite, customUSD > 0 else { return nil }
        return customUSD
    }
}

/// The plan choice, in the App Group defaults so the widgets read the same allowance as the app.
public enum CopilotPreferences {
    public static let planKey = "copilot.plan"
    public static let customUSDKey = "copilot.customUSD"

    public static var shared: UserDefaults { UserDefaults(suiteName: AppGroup.identifier) ?? .standard }

    public static func allowance(defaults: UserDefaults = shared) -> CopilotAllowance {
        let plan = defaults.string(forKey: planKey).flatMap(CopilotPlan.init(rawValue:)) ?? .pro
        let custom = defaults.object(forKey: customUSDKey) as? Double
        return CopilotAllowance(plan: plan, customUSD: custom)
    }

    public static func setPlan(_ plan: CopilotPlan, defaults: UserDefaults = shared) {
        defaults.set(plan.rawValue, forKey: planKey)
    }

    /// Nil (or a non-positive amount) clears it.
    public static func setCustomUSD(_ amount: Double?, defaults: UserDefaults = shared) {
        if let amount, amount.isFinite, amount > 0 {
            defaults.set(amount, forKey: customUSDKey)
        } else {
            defaults.removeObject(forKey: customUSDKey)
        }
    }
}

/// GitHub Copilot usage through GitHub's official billing REST API, with the user's own personal access token.
///
/// - `GET https://api.github.com/user` → `login`, read once per token.
///   https://docs.github.com/en/rest/users/users#get-the-authenticated-user
/// - `GET /users/{username}/settings/billing/ai_credit/usage?year=&month=` → this month's AI-credit usage items
///   (`product`, `sku`, `model`, `unitType`, `pricePerUnit`, `grossQuantity`, `grossAmount`, `discountQuantity`,
///   `discountAmount`, `netQuantity`, `netAmount`). Without `day` the report covers the whole month.
///   https://docs.github.com/en/rest/billing/usage#get-billing-ai-credit-usage-report-for-a-user
/// - On 404 only: `GET /users/{username}/settings/billing/premium_request/usage?year=&month=` (legacy request billing,
///   same response shape, `unitType` "requests").
///   https://docs.github.com/en/rest/billing/usage#get-billing-premium-request-usage-report-for-a-user
///
/// Headers: `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2026-03-10`
/// (https://docs.github.com/en/rest/about-the-rest-api/api-versions).
///
/// Token: a fine-grained PAT with the account permission "Plan" (read) is listed for these four user billing
/// endpoints (https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens#user-permissions-for-plan).
/// GitHub's billing tutorial instead says these endpoints need a classic PAT and do not support fine-grained ones
/// (https://docs.github.com/en/billing/tutorials/automate-usage-reporting#prerequisites); the classic scope is not
/// documented. Unverified against a live account: which of the two GitHub actually accepts.
///
/// User endpoints cover only plans billed to the personal account; a seat billed through an organization or
/// enterprise (Business, Enterprise) is not included (https://docs.github.com/en/rest/billing/usage).
///
/// The reading: `grossAmount` (all usage this month, at list price) against the plan's included credits, as a
/// `.spendLimit` lane resetting at 00:00 UTC on the 1st of next month — fixed, not the subscription billing date
/// (https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals). `discountAmount` is the
/// part covered by included usage and `netAmount` the billed part
/// (https://docs.github.com/en/billing/tutorials/automate-usage-reporting#step-5-interpret-usage-and-cost-fields-in-the-api-response),
/// so a positive `netAmount` is shown as extra usage.
public struct CopilotProvider: UsageProvider {
    public static let providerID = "copilot"
    public static let name = "GitHub Copilot"
    public let id = CopilotProvider.providerID
    public let displayName = CopilotProvider.name

    static let apiBase = URL(string: "https://api.github.com")!
    static let apiVersion = "2026-03-10"

    private let transport: any HTTPTransport
    private let tokens: any AccessTokenSource
    private let enabled: @Sendable () -> Bool
    private let allowance: @Sendable () -> CopilotAllowance
    private let clock: @Sendable () -> Date
    private let gate = BackoffGate()
    private let logins = LoginMemo()

    public init(transport: any HTTPTransport = URLSessionTransport(),
                tokens: any AccessTokenSource,
                isEnabled: @escaping @Sendable () -> Bool = { true },
                allowance: @escaping @Sendable () -> CopilotAllowance = { CopilotPreferences.allowance() },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.tokens = tokens
        self.enabled = isEnabled
        self.allowance = allowance
        self.clock = clock
    }

    /// Reads the token from `store` (the shared Keychain in the app and the widget); enabled only while one is saved.
    public init(store: any CredentialStore, transport: any HTTPTransport = URLSessionTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(transport: transport,
                  tokens: StoredTokenSource(store: store, tokenKey: CredentialKey.gitHubCopilotToken),
                  isEnabled: { Self.hasKey(in: store) },
                  clock: clock)
    }

    public var isEnabled: Bool { enabled() }

    public static func hasKey(in store: any CredentialStore) -> Bool {
        guard let key = try? store.read(CredentialKey.gitHubCopilotToken) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checks a pasted token with one reading before it is saved. Throws `.unauthenticated` for a rejected token,
    /// `.decoding` when GitHub has no usage report for this account.
    public static func validate(key: String, transport: any HTTPTransport = URLSessionTransport()) async throws -> UsageInfo {
        try await CopilotProvider(transport: transport, tokens: FixedKey(key: key)).fetchUsage()
    }

    public func fetchUsage() async throws -> UsageInfo {
        let now = clock()
        if let until = await gate.check(now: now) { throw UsageProviderError.rateLimited(until: until) }
        let token = try await tokens.credentials().token
        let login = try await login(token: token, now: now)
        let month = Self.utcMonth(containing: now)

        let (data, response) = try await get(Self.reportURL(login: login, report: "ai_credit", year: month.year,
                                                            month: month.month), token: token)
        if response.statusCode == 404 {
            let (legacy, legacyResponse) = try await get(Self.reportURL(login: login, report: "premium_request",
                                                                        year: month.year, month: month.month),
                                                         token: token)
            if legacyResponse.statusCode == 404 { throw UsageProviderError.decoding }   // no Copilot report here
            try await check(legacyResponse, token: token, now: now)
            return try Self.map(report: legacy, unit: .premiumRequests, allowance: allowance(), now: now)
        }
        try await check(response, token: token, now: now)
        return try Self.map(report: data, unit: .aiCredits, allowance: allowance(), now: now)
    }

    private func login(token: String, now: Date) async throws -> String {
        if let known = await logins.login(for: token) { return known }
        let (data, response) = try await get(Self.apiBase.appendingPathComponent("user"), token: token)
        try await check(response, token: token, now: now)
        guard let login = Self.login(from: data) else { throw UsageProviderError.decoding }
        await logins.remember(login, for: token)
        return login
    }

    /// 401 → unauthenticated. 403/429 with GitHub's rate-limit signals (`x-ratelimit-remaining: 0` or
    /// `retry-after`) → rateLimited; any other 403 → unauthenticated (missing permission).
    /// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#exceeding-the-rate-limit
    private func check(_ response: HTTPURLResponse, token: String, now: Date) async throws {
        let status = response.statusCode
        if status == 200 { return }
        if status == 429 || (status == 403 && Self.isRateLimit(response)) {
            let until = Self.rateLimitReset(response, now: now)
            await gate.block(until: until)
            throw UsageProviderError.rateLimited(until: until)
        }
        switch status {
        case 401, 403:
            await logins.forget(token)
            throw UsageProviderError.unauthenticated
        case 404: throw UsageProviderError.decoding
        default: throw UsageProviderError.server(status: status)
        }
    }

    static func isRateLimit(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
            || response.value(forHTTPHeaderField: "retry-after") != nil
    }

    /// `retry-after` (seconds) first, then `x-ratelimit-reset` (UTC epoch seconds), else a minute from now.
    static func rateLimitReset(_ response: HTTPURLResponse, now: Date) -> Date {
        if response.value(forHTTPHeaderField: "retry-after") == nil,
           let raw = response.value(forHTTPHeaderField: "x-ratelimit-reset"), let epoch = Double(raw),
           epoch.isFinite, epoch > now.timeIntervalSince1970 {
            return Date(timeIntervalSince1970: epoch)
        }
        return RetryAfter.date(from: response, now: now)
    }

    private func get(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AImana", forHTTPHeaderField: "User-Agent")   // GitHub rejects requests without one
        do {
            return try await transport.send(request)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.network
        }
    }

    static func reportURL(login: String, report: String, year: Int, month: Int) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let user = login.addingPercentEncoding(withAllowedCharacters: allowed) ?? login
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/users/\(user)/settings/billing/\(report)/usage"
        components.queryItems = [URLQueryItem(name: "year", value: String(year)),
                                 URLQueryItem(name: "month", value: String(month))]
        return components.url!
    }

    // MARK: Mapping (pure, unit-tested)

    enum Unit { case aiCredits, premiumRequests }

    private struct User: Decodable { let login: String? }

    private struct Item: Decodable {
        let product: Lossy<String>?
        let unitType: Lossy<String>?
        let grossQuantity: Lossy<Double>?
        let grossAmount: Lossy<Double>?
        let netAmount: Lossy<Double>?
    }

    private struct Report: Decodable { let usageItems: [Lossy<Item>] }

    static func login(from data: Data) -> String? {
        guard let login = (try? JSONDecoder().decode(User.self, from: data))?.login?
            .trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty else { return nil }
        return login
    }

    /// The UTC calendar month containing `date`: its number and bounds. AI credits and legacy premium requests both
    /// reset at 00:00:00 UTC on the 1st.
    static func utcMonth(containing date: Date) -> (year: Int, month: Int, start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        let interval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: date, duration: 30 * 86400)
        return (parts.year ?? 1970, parts.month ?? 1, interval.start, interval.end)
    }

    static func map(report: Data, unit: Unit, allowance: CopilotAllowance, now: Date) throws -> UsageInfo {
        guard let body = try? JSONDecoder().decode(Report.self, from: report) else {
            throw UsageProviderError.decoding
        }
        func finite(_ value: Lossy<Double>?) -> Double {
            guard let value = value?.value, value.isFinite else { return 0 }
            return value
        }
        // Every AI credit draws on the Copilot allowance (Chat, CLI, cloud agent, Spark…), so the whole AI-credit
        // report counts. The legacy report is narrowed to Copilot request items.
        let items = body.usageItems.compactMap(\.value).filter { item in
            switch unit {
            case .aiCredits: return true
            case .premiumRequests:
                let product = item.product?.value?.lowercased() ?? ""
                let unitType = item.unitType?.value?.lowercased() ?? "requests"
                return product.contains("copilot") && unitType == "requests"
            }
        }
        let gross = items.reduce(0) { $0 + finite($1.grossAmount) }
        let net = items.reduce(0) { $0 + finite($1.netAmount) }
        let month = utcMonth(containing: now)
        let minutes = Int(month.end.timeIntervalSince(month.start) / 60)

        var windows: [UsageWindow] = []
        switch unit {
        case .aiCredits:
            if let included = allowance.includedUSD, included > 0 {
                windows.append(UsageWindow(kind: .spendLimit, usedPercent: max(0, gross) / included * 100,
                                           windowMinutes: minutes, resetsAt: month.end))
            }
        case .premiumRequests:
            if let included = allowance.plan.legacyPremiumRequests {
                let requests = items.reduce(0) { $0 + finite($1.grossQuantity) }
                windows.append(UsageWindow(kind: .spendLimit, usedPercent: max(0, requests) / included * 100,
                                           windowMinutes: minutes, resetsAt: month.end))
            }
        }

        var details = [UsageDetail(kind: .monthlySpend, remaining: 0, currency: "USD", used: max(0, gross))]
        if net > 0.005 {
            details.append(UsageDetail(kind: .extraUsage, remaining: 0, currency: "USD", used: net))
        }
        return UsageInfo(providerID: providerID, providerName: name, windows: windows,
                         plan: allowance.plan.badge, lastUpdated: now, details: details)
    }
}

/// The token owner's login, so later refreshes skip `GET /user`. Keyed by the token, so a new token starts over.
private actor LoginMemo {
    private var token: String?
    private var value: String?

    func login(for token: String) -> String? { token == self.token ? value : nil }
    func remember(_ login: String, for token: String) { self.token = token; value = login }
    func forget(_ token: String) { if token == self.token { self.token = nil; value = nil } }
}
