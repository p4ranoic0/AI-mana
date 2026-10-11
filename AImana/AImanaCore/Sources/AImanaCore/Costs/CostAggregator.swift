import Foundation

/// Folds `CostEvent`s into per-day, per-model costs. Duplicate keys count once (streamed partial rows and
/// resumed/forked sessions repeat the same response), keeping the version with the most output.
public struct CostAggregator {
    private let priceProvider: String
    private let pricing: PricingTable
    private let calendar: Calendar
    private var events: [String: CostEvent] = [:]

    public init(priceProvider: String, pricing: PricingTable, calendar: Calendar = .current) {
        self.priceProvider = priceProvider
        self.pricing = pricing
        self.calendar = calendar
    }

    public mutating func add(_ event: CostEvent) {
        if let existing = events[event.key], existing.tokens.output >= event.tokens.output { return }
        events[event.key] = event
    }

    public func report(providerID: String, now: Date, days: Int) -> CostReport {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now))
            ?? now
        let cutoff = formatter.string(from: start)

        var perDay: [String: [String: TokenUsage]] = [:]
        for event in events.values {
            let day = formatter.string(from: event.timestamp)
            guard day >= cutoff else { continue }
            perDay[day, default: [:]][event.model, default: TokenUsage()] =
                (perDay[day]?[event.model] ?? TokenUsage()) + event.tokens
        }

        let built = perDay.keys.sorted().map { day -> DailyCost in
            var tokens = TokenUsage()
            var usd = 0.0
            var unpriced = 0
            var models: [ModelCost] = []
            for (model, used) in perDay[day] ?? [:] {
                tokens = tokens + used
                if let price = pricing.price(provider: priceProvider, model: model) {
                    let cost = price.cost(of: used)
                    usd += cost
                    models.append(ModelCost(model: model, tokens: used, usd: cost))
                } else {
                    unpriced += used.total
                    models.append(ModelCost(model: model, tokens: used, usd: nil))
                }
            }
            models.sort { ($0.usd ?? -1) > ($1.usd ?? -1) }
            return DailyCost(day: day, tokens: tokens, usd: usd, unpricedTokens: unpriced, models: models)
        }
        return CostReport(providerID: providerID, generatedAt: now, days: built)
    }
}
