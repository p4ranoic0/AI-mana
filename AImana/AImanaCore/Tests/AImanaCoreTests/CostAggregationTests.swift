import Foundation
import Testing
@testable import AImanaCore

@Suite struct CostAggregationTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    let now = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!

    var pricing: PricingTable {
        PricingTable(prices: [
            "anthropic/claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
            "openai/gpt-6-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5),
        ])
    }

    private func event(_ key: String, _ iso: String, model: String, _ tokens: TokenUsage) -> CostEvent {
        CostEvent(key: key, timestamp: ISO8601DateFormatter().date(from: iso)!, model: model, tokens: tokens)
    }

    @Test func costIsTokensTimesPricePerMillion() {
        let e = event("a", "2026-10-04T08:00:00Z", model: "claude-opus-5",
                      TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000))
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        agg.add(e)
        let report = agg.report(providerID: "claude", now: now, days: 30)
        #expect(abs(report.days[0].usd - (5 + 25 + 0.5 + 6.25)) < 1e-9)
        #expect(report.days[0].models[0].usd != nil)
    }

    @Test func groupsByLocalDayAndKeepsAscendingOrder() {
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        agg.add(event("a", "2026-10-04T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 1_000_000)))
        agg.add(event("b", "2026-10-02T23:59:00Z", model: "claude-opus-5", TokenUsage(input: 2_000_000)))
        agg.add(event("c", "2026-10-03T00:01:00Z", model: "claude-opus-5", TokenUsage(input: 3_000_000)))
        let days = agg.report(providerID: "claude", now: now, days: 30).days
        #expect(days.map(\.day) == ["2026-10-02", "2026-10-03", "2026-10-04"])
        #expect(days.map(\.usd) == [10, 15, 5])
    }

    @Test func dayBoundaryFollowsTheCalendarTimeZone() {
        var lima = Calendar(identifier: .gregorian); lima.timeZone = TimeZone(identifier: "America/Lima")!
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: lima)
        // 02:00Z on the 4th is 21:00 on the 3rd in Lima.
        agg.add(event("a", "2026-10-04T02:00:00Z", model: "claude-opus-5", TokenUsage(input: 1_000_000)))
        #expect(agg.report(providerID: "claude", now: now, days: 30).days.first?.day == "2026-10-03")
    }

    @Test func duplicatesAreCountedOnceKeepingTheFinalStreamedValue() {
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        agg.add(event("msg:req", "2026-10-04T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 100, output: 10)))
        agg.add(event("msg:req", "2026-10-04T08:00:01Z", model: "claude-opus-5", TokenUsage(input: 100, output: 900)))
        agg.add(event("msg:req", "2026-10-04T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 100, output: 10)))
        let day = agg.report(providerID: "claude", now: now, days: 30).days[0]
        #expect(day.tokens.output == 900)
        #expect(day.tokens.input == 100)
    }

    @Test func unknownModelsAreCountedAsTokensButNotPriced() {
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        agg.add(event("a", "2026-10-04T08:00:00Z", model: "claude-mystery", TokenUsage(input: 500, output: 500)))
        agg.add(event("b", "2026-10-04T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 1_000_000)))
        let day = agg.report(providerID: "claude", now: now, days: 30).days[0]
        #expect(day.unpricedTokens == 1000)
        #expect(day.usd == 5)
        #expect(day.models.first { $0.model == "claude-mystery" }?.usd == nil)
        #expect(day.tokens.input == 1_000_500)
    }

    @Test func eventsOutsideTheWindowAreDropped() {
        var agg = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        agg.add(event("old", "2026-08-01T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 1_000_000)))
        agg.add(event("new", "2026-10-04T08:00:00Z", model: "claude-opus-5", TokenUsage(input: 1_000_000)))
        #expect(agg.report(providerID: "claude", now: now, days: 30).days.map(\.day) == ["2026-10-04"])
    }

    @Test func openAIPricingUsesProviderScope() {
        var agg = CostAggregator(priceProvider: "openai", pricing: pricing, calendar: utc)
        agg.add(event("a", "2026-10-04T08:00:00Z", model: "gpt-6-sol", TokenUsage(input: 1_000_000, output: 1_000_000)))
        #expect(agg.report(providerID: "codex", now: now, days: 30).days[0].usd == 12)
        // The same model id under the other vendor must not be priced.
        var other = CostAggregator(priceProvider: "anthropic", pricing: pricing, calendar: utc)
        other.add(event("a", "2026-10-04T08:00:00Z", model: "gpt-6-sol", TokenUsage(input: 1_000_000)))
        #expect(other.report(providerID: "x", now: now, days: 30).days[0].unpricedTokens == 1_000_000)
    }

    // MARK: Pricing table

    @Test func parsesModelsDevCatalogKeepingOnlyKnownVendorsWithPrices() throws {
        let json = """
        {"anthropic":{"models":{"claude-opus-5":{"cost":{"input":5,"output":25,"cache_read":0.5,"cache_write":6.25}},
                                "claude-no-price":{"name":"x"}}},
         "openai":{"models":{"gpt-6-sol":{"cost":{"input":2,"output":10,"cache_read":0.2}}}},
         "someone-else":{"models":{"m":{"cost":{"input":1,"output":1}}}}}
        """
        let table = try #require(PricingTable.fromModelsDev(Data(json.utf8)))
        #expect(table.price(provider: "anthropic", model: "claude-opus-5") == ModelPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25))
        #expect(table.price(provider: "openai", model: "gpt-6-sol")?.cacheWrite == 0)   // missing → 0
        #expect(table.price(provider: "anthropic", model: "claude-no-price") == nil)
        #expect(table.price(provider: "someone-else", model: "m") == nil)
    }

    @Test func lookupToleratesDateSuffixAndContextTag() {
        #expect(pricing.price(provider: "anthropic", model: "claude-opus-5-20261001") != nil)
        #expect(pricing.price(provider: "anthropic", model: "claude-opus-5[1m]") != nil)
        #expect(pricing.price(provider: "anthropic", model: "claude-other") == nil)
    }

    @Test func garbageCatalogYieldsNil() {
        #expect(PricingTable.fromModelsDev(Data("nope".utf8)) == nil)
    }
}
