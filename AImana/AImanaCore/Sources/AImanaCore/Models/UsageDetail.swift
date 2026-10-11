import Foundation

/// Extra balances a provider reports next to its rate-limit windows (credits, reset credits).
public struct UsageDetail: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Promotional Claude cloud-session credit, in dollars.
        case cloudCredits
        /// Prepaid Codex credit balance, in dollars.
        case creditBalance
        /// Codex rate-limit reset credits (a count).
        case resetCredits
        /// Claude "extra usage": paid usage beyond the plan, billed against a monthly spending cap.
        /// Distinct from `.cloudCredits` (a promotional grant for cloud sessions).
        case extraUsage
        /// Pay-as-you-go API spend this calendar month (UTC), in dollars, in `used` (OpenRouter).
        case monthlySpend
    }

    public let kind: Kind
    /// Dollars for the credit kinds, a count for `.resetCredits`.
    public let remaining: Double
    public let limit: Double?
    public let currency: String?
    public let expiresAt: Date?
    /// For `.resetCredits`: how many can be applied right now. For `.creditBalance`: 0 when the provider says the
    /// balance cannot pay for API calls right now (DeepSeek `is_available: false`, a Moonshot or xAI balance at or
    /// below zero); nil when it can or the provider does not say.
    public let usable: Double?
    /// For `.extraUsage`: amount spent this month. Older snapshots lack this key.
    public let used: Double?

    /// Kind plus currency: a provider may report one balance per currency (DeepSeek: CNY and USD).
    public var id: String { currency.map { "\(kind.rawValue).\($0)" } ?? kind.rawValue }

    /// A prepaid balance the provider flagged as unable to pay for API calls right now (`usable == 0`).
    public var isExhaustedBalance: Bool { kind == .creditBalance && usable == 0 }

    public init(kind: Kind, remaining: Double, limit: Double? = nil, currency: String? = nil,
                expiresAt: Date? = nil, usable: Double? = nil, used: Double? = nil) {
        self.kind = kind
        self.remaining = remaining
        self.limit = limit
        self.currency = currency
        self.expiresAt = expiresAt
        self.usable = usable
        self.used = used
    }

    public var title: String {
        switch kind {
        case .cloudCredits: CoreStrings.text("Cloud credits")
        case .creditBalance: CoreStrings.text("Credit balance")
        case .resetCredits: CoreStrings.text("Reset credits")
        case .extraUsage: CoreStrings.text("Extra usage")
        case .monthlySpend: CoreStrings.text("API spend")
        }
    }

    public var symbol: String {
        switch kind {
        case .cloudCredits: "cloud"
        case .creditBalance: "creditcard"
        case .resetCredits: "arrow.counterclockwise.circle"
        case .extraUsage: "plus.circle"
        case .monthlySpend: "chart.bar"
        }
    }

    /// Share already spent (0...1) when there is a known allowance.
    public var usedFraction: Double? {
        guard let limit, limit > 0 else { return nil }
        if let used { return min(1, max(0, used / limit)) }
        return min(1, max(0, (limit - remaining) / limit))
    }

    public func summary(locale: Locale? = nil) -> String {
        switch kind {
        case .cloudCredits:
            let left = Self.money(remaining, currency, locale: locale)
            guard let limit else { return CoreStrings.format("%@ left", locale: locale, left) }
            return CoreStrings.format("%@ left of %@", locale: locale, left,
                                      Self.money(limit, currency, locale: locale))
        case .creditBalance:
            return Self.money(remaining, currency, locale: locale)
        case .resetCredits:
            let count = Int(remaining.rounded())
            guard let usable else { return CoreStrings.format("%d available", locale: locale, count) }
            let ready = Int(usable.rounded())
            return ready > 0
                ? CoreStrings.format("%d available · %d usable now", locale: locale, count, ready)
                : CoreStrings.format("%d available · none usable now", locale: locale, count)
        case .extraUsage:
            let spent = Self.money(used ?? 0, currency, locale: locale)
            guard let limit else { return CoreStrings.format("%@ spent this month", locale: locale, spent) }
            return CoreStrings.format("%@ of %@ this month", locale: locale, spent,
                                      Self.money(limit, currency, locale: locale))
        case .monthlySpend:
            return CoreStrings.format("%@ this month", locale: locale, Self.money(used ?? 0, currency, locale: locale))
        }
    }

    public func caption(now: Date = Date(), locale: Locale? = nil) -> String? {
        if isExhaustedBalance { return CoreStrings.text("Too low for API calls", locale: locale) }
        guard let expiresAt else { return nil }
        guard expiresAt > now else { return CoreStrings.text("Expired", locale: locale) }
        return CoreStrings.format("Expires in %@", locale: locale,
                                  UsageFormatter.resetCountdown(to: expiresAt, now: now, locale: locale))
    }

    private static func money(_ value: Double, _ code: String?, locale: Locale?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale ?? .current
        formatter.currencyCode = code ?? "USD"
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
