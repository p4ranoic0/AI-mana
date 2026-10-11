import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension CredentialKey {
    /// The user's own DeepSeek API key (`sk-…`), pasted in Settings.
    static let deepSeekAPIKey = "deepseek.apiKey"
    /// The user's own Moonshot / Kimi Open Platform API key, from platform.kimi.ai or platform.kimi.com.
    static let moonshotAPIKey = "moonshot.apiKey"
    /// An xAI *management* key (xAI Console → Settings → Management Keys), not an inference key.
    static let xAIManagementKey = "xai.managementKey"
}

/// What sets one prepaid-balance API apart from another: where to ask and how to read the answer.
/// Every balance provider shares `BalanceProvider` for the request, error mapping and backoff.
public struct BalanceDescriptor: Sendable {
    /// One balance URL and the currency its amounts are in, when the response does not say.
    public struct Endpoint: Sendable, Equatable {
        public let url: URL
        public let currency: String?
    }

    enum Route: Sendable {
        /// Hosts tried in order: each platform rejects the other's keys with 401, so the first host that accepts
        /// the key is the user's region. The answer is remembered for that key.
        case alternatives([Endpoint])
        /// The balance URL needs an ID read first with the same key (xAI: the key's team). Remembered for that key.
        case scoped(lookup: URL, scopeID: @Sendable (Data) -> String?, balance: @Sendable (String) -> Endpoint)
    }

    public let id: String
    public let name: String
    public let credentialKey: String
    let route: Route
    /// Balance response (and the endpoint's currency) to balance entries. Throws `.decoding` for a foreign shape.
    let decode: @Sendable (Data, String?) throws -> [UsageDetail]

    /// The three balance providers, in the order Settings lists them.
    public static let all: [BalanceDescriptor] = [deepSeek, moonshot, xAI]

    public static func descriptor(id: String) -> BalanceDescriptor? { all.first { $0.id == id } }

    /// DeepSeek: `GET https://api.deepseek.com/user/balance` with the API key as Bearer token.
    /// Amounts are strings, one entry per currency (CNY or USD).
    /// https://api-docs.deepseek.com/api/get-user-balance
    public static let deepSeek = BalanceDescriptor(
        id: "deepseek", name: "DeepSeek", credentialKey: CredentialKey.deepSeekAPIKey,
        route: .alternatives([Endpoint(url: URL(string: "https://api.deepseek.com/user/balance")!, currency: nil)]),
        decode: { data, _ in try BalanceDecoding.deepSeek(data) })

    /// Moonshot / Kimi Open Platform: `GET /v1/users/me/balance` with the API key as Bearer token.
    /// - International (platform.kimi.ai): `https://api.moonshot.ai`, amounts in USD.
    ///   https://platform.kimi.ai/docs/api/balance
    /// - China (platform.kimi.com): `https://api.moonshot.cn`, amounts in CNY (人民币元).
    ///   https://platform.kimi.com/docs/api/balance
    /// Keys of one platform get 401 on the other, so the region is found by trying both; no setting needed.
    public static let moonshot = BalanceDescriptor(
        id: "moonshot", name: "Moonshot (Kimi)", credentialKey: CredentialKey.moonshotAPIKey,
        route: .alternatives([
            Endpoint(url: URL(string: "https://api.moonshot.ai/v1/users/me/balance")!, currency: "USD"),
            Endpoint(url: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!, currency: "CNY"),
        ]),
        decode: { data, currency in try BalanceDecoding.moonshot(data, currency: currency ?? "USD") })

    /// xAI: the prepaid balance is only on the Management API, with a management key (an ordinary inference key's
    /// `GET https://api.x.ai/v1/api-key` returns key metadata and team ID, but no balance).
    /// - `GET https://management-api.x.ai/auth/management-keys/validation` → `teamId` of the management key.
    ///   https://docs.x.ai/developers/rest-api-reference/management/auth
    /// - `GET https://management-api.x.ai/v1/billing/teams/{team_id}/prepaid/balance` → `total.val` in USD cents,
    ///   negative for credit (a $10 purchase reads `"-1000"`).
    ///   https://docs.x.ai/docs/management-api/billing
    ///   https://docs.x.ai/developers/management-api-guide
    public static let xAI = BalanceDescriptor(
        id: "xai", name: "xAI", credentialKey: CredentialKey.xAIManagementKey,
        route: .scoped(
            lookup: URL(string: "https://management-api.x.ai/auth/management-keys/validation")!,
            scopeID: { BalanceDecoding.xAITeamID($0) },
            balance: { team in
                var allowed = CharacterSet.urlPathAllowed
                allowed.remove("/")
                let escaped = team.addingPercentEncoding(withAllowedCharacters: allowed) ?? team
                return Endpoint(url: URL(string: "https://management-api.x.ai/v1/billing/teams/\(escaped)/prepaid/balance")!,
                                currency: "USD")
            }),
        decode: { data, _ in try BalanceDecoding.xAI(data) })
}

/// A prepaid API balance read with the user's own key, through the provider's official API. No quota lanes:
/// the reading is one `.creditBalance` entry per currency, in the currency the provider reports (never converted).
/// 401/403 → `.unauthenticated`, 429 → `.rateLimited` (remembered), anything else → `.server`.
public struct BalanceProvider: UsageProvider {
    public let descriptor: BalanceDescriptor
    public var id: String { descriptor.id }
    public var displayName: String { descriptor.name }

    private let transport: any HTTPTransport
    private let tokens: any AccessTokenSource
    private let enabled: @Sendable () -> Bool
    private let clock: @Sendable () -> Date
    private let gate = BackoffGate()
    private let memo = RouteMemo()

    public init(descriptor: BalanceDescriptor, transport: any HTTPTransport = URLSessionTransport(),
                tokens: any AccessTokenSource,
                isEnabled: @escaping @Sendable () -> Bool = { true },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.descriptor = descriptor
        self.transport = transport
        self.tokens = tokens
        self.enabled = isEnabled
        self.clock = clock
    }

    /// Reads the key from `store` (the shared Keychain in the app and the widget); enabled only while one is saved.
    public init(descriptor: BalanceDescriptor, store: any CredentialStore,
                transport: any HTTPTransport = URLSessionTransport(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(descriptor: descriptor, transport: transport,
                  tokens: StoredTokenSource(store: store, tokenKey: descriptor.credentialKey),
                  isEnabled: { Self.hasKey(descriptor, in: store) },
                  clock: clock)
    }

    public var isEnabled: Bool { enabled() }

    public static func hasKey(_ descriptor: BalanceDescriptor, in store: any CredentialStore) -> Bool {
        guard let key = try? store.read(descriptor.credentialKey) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checks a pasted key with one reading before it is saved. Throws `.unauthenticated` for a rejected key.
    public static func validate(_ descriptor: BalanceDescriptor, key: String,
                                transport: any HTTPTransport = URLSessionTransport()) async throws -> UsageInfo {
        try await BalanceProvider(descriptor: descriptor, transport: transport, tokens: FixedKey(key: key)).fetchUsage()
    }

    public func fetchUsage() async throws -> UsageInfo {
        let now = clock()
        if let until = await gate.check(now: now) { throw UsageProviderError.rateLimited(until: until) }
        let token = try await tokens.credentials().token
        let (data, currency) = try await readBalance(token: token, now: now)
        let details = try descriptor.decode(data, currency)
        return UsageInfo(providerID: descriptor.id, providerName: descriptor.name, windows: [],
                         plan: nil, lastUpdated: now, details: details)
    }

    private func readBalance(token: String, now: Date) async throws -> (Data, String?) {
        switch descriptor.route {
        case .alternatives(let endpoints):
            let first = await memo.endpoint(for: token) ?? 0
            let order = [first] + endpoints.indices.filter { $0 != first }
            for (attempt, index) in order.enumerated() {
                let (data, response) = try await get(endpoints[index].url, token: token)
                let rejected = response.statusCode == 401 || response.statusCode == 403
                if rejected, attempt < order.count - 1 { continue }   // maybe a key of the other region
                try await check(response, now: now)
                await memo.remember(endpoint: index, for: token)
                return (data, endpoints[index].currency)
            }
            throw UsageProviderError.unauthenticated   // no endpoints
        case .scoped(let lookup, let scopeID, let balance):
            let scope: String
            if let known = await memo.scope(for: token) {
                scope = known
            } else {
                let (data, response) = try await get(lookup, token: token)
                try await check(response, now: now)
                guard let found = scopeID(data) else { throw UsageProviderError.decoding }
                await memo.remember(scope: found, for: token)
                scope = found
            }
            let endpoint = balance(scope)
            let (data, response) = try await get(endpoint.url, token: token)
            if response.statusCode == 401 || response.statusCode == 403 { await memo.forget(token) }
            try await check(response, now: now)
            return (data, endpoint.currency)
        }
    }

    private func check(_ response: HTTPURLResponse, now: Date) async throws {
        switch response.statusCode {
        case 200: return
        case 401, 403: throw UsageProviderError.unauthenticated
        case 429:
            let until = RetryAfter.date(from: response, now: now)
            await gate.block(until: until)
            throw UsageProviderError.rateLimited(until: until)
        default: throw UsageProviderError.server(status: response.statusCode)
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
}

/// Which region host or team a key belongs to, so later refreshes go straight there. Keyed by the key itself,
/// so saving a different key starts over.
private actor RouteMemo {
    private var key: String?
    private var endpointIndex: Int?
    private var scopeID: String?

    func endpoint(for token: String) -> Int? { token == key ? endpointIndex : nil }
    func scope(for token: String) -> String? { token == key ? scopeID : nil }

    func remember(endpoint: Int, for token: String) {
        if token != key { key = token; scopeID = nil }
        endpointIndex = endpoint
    }

    func remember(scope: String, for token: String) {
        if token != key { key = token; endpointIndex = nil }
        scopeID = scope
    }

    func forget(_ token: String) {
        if token == key { key = nil; endpointIndex = nil; scopeID = nil }
    }
}

// MARK: - Decoding (pure, unit-tested)

enum BalanceDecoding {
    /// An amount sent as a JSON string (`"110.00"`) or number. Non-finite or unparsable values are nil.
    struct Amount: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number.isFinite ? number : nil
            } else if let text = try? container.decode(String.self),
                      let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite {
                value = number
            } else {
                value = nil
            }
        }
    }

    private static func currencyCode(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.count == 3, code.allSatisfy(\.isLetter) else { return nil }
        return code
    }

    // DeepSeek

    private struct DeepSeekInfo: Decodable {
        let currency: String?
        let total_balance: Amount?
    }

    private struct DeepSeekBalance: Decodable {
        let is_available: Lossy<Bool>?
        let balance_infos: [Lossy<DeepSeekInfo>]?
    }

    /// One balance per currency. `is_available: false` (balance too low for API calls) marks each as not usable.
    static func deepSeek(_ data: Data) throws -> [UsageDetail] {
        guard let body = try? JSONDecoder().decode(DeepSeekBalance.self, from: data),
              body.is_available != nil || body.balance_infos != nil else {
            throw UsageProviderError.decoding
        }
        let blocked = body.is_available?.value == false
        return (body.balance_infos ?? []).compactMap(\.value).compactMap { info in
            guard let currency = currencyCode(info.currency), let total = info.total_balance?.value else { return nil }
            return UsageDetail(kind: .creditBalance, remaining: total, currency: currency,
                               usable: blocked || total <= 0 ? 0 : nil)
        }
    }

    // Moonshot

    private struct MoonshotData: Decodable { let available_balance: Amount? }
    private struct MoonshotBalance: Decodable { let data: MoonshotData? }

    /// `available_balance` (cash plus vouchers); API calls stop at zero or below.
    static func moonshot(_ data: Data, currency: String) throws -> [UsageDetail] {
        guard let body = try? JSONDecoder().decode(MoonshotBalance.self, from: data),
              let available = body.data?.available_balance?.value else {
            throw UsageProviderError.decoding
        }
        return [UsageDetail(kind: .creditBalance, remaining: available, currency: currency,
                            usable: available <= 0 ? 0 : nil)]
    }

    // xAI

    private struct XAIValidation: Decodable { let teamId: String? }
    private struct XAICents: Decodable { let val: Amount? }
    private struct XAIBalance: Decodable { let total: XAICents? }

    static func xAITeamID(_ data: Data) -> String? {
        guard let team = (try? JSONDecoder().decode(XAIValidation.self, from: data))?.teamId?
            .trimmingCharacters(in: .whitespacesAndNewlines), !team.isEmpty else { return nil }
        return team
    }

    /// `total.val` is USD cents with purchases negative, so the spendable balance is its negation.
    static func xAI(_ data: Data) throws -> [UsageDetail] {
        guard let body = try? JSONDecoder().decode(XAIBalance.self, from: data),
              let cents = body.total?.val?.value else {
            throw UsageProviderError.decoding
        }
        let dollars = -cents / 100
        return [UsageDetail(kind: .creditBalance, remaining: dollars == 0 ? 0 : dollars, currency: "USD",
                            usable: dollars <= 0 ? 0 : nil)]
    }
}
