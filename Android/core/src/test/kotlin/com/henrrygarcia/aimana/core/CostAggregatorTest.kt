package com.henrrygarcia.aimana.core

import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.*
import org.junit.Test

class CostAggregatorTest {
    private val now = Instant.parse("2026-10-04T12:00:00Z")
    private val prices = PricingTable(mapOf("anthropic/claude-opus-5" to ModelPrice(5.0,25.0,0.5,6.25), "openai/gpt-6-sol" to ModelPrice(2.0,10.0)))
    @Test fun tokenPriceMatchesSwift() {
        val agg = CostAggregator("anthropic",prices,ZoneOffset.UTC)
        agg.add(CostEvent("a",now,"claude-opus-5",TokenUsage(1_000_000,1_000_000,1_000_000,1_000_000)))
        assertEquals(36.75,agg.report("claude",now,30).days.single().usd,1e-9)
    }
    @Test fun duplicateKeepsMostOutput() {
        val agg = CostAggregator("anthropic",prices,ZoneOffset.UTC)
        agg.add(CostEvent("a",now,"claude-opus-5",TokenUsage(100,10)))
        agg.add(CostEvent("a",now.plusSeconds(1),"claude-opus-5",TokenUsage(100,900)))
        agg.add(CostEvent("a",now,"claude-opus-5",TokenUsage(100,10)))
        assertEquals(900L,agg.report("claude",now,30).days.single().tokens.output)
    }
    @Test fun unknownModelsKeepTokensWithoutPrice() {
        val agg = CostAggregator("anthropic",prices,ZoneOffset.UTC)
        agg.add(CostEvent("a",now,"mystery",TokenUsage(500,500)))
        assertEquals(1000L,agg.report("claude",now,30).days.single().unpricedTokens)
    }
    @Test fun modelSuffixAndVendorAreScoped() {
        assertNotNull(prices.price("anthropic","claude-opus-5-20261001"))
        assertNotNull(prices.price("anthropic","claude-opus-5[1m]"))
        assertNull(prices.price("anthropic","gpt-6-sol"))
    }
    @Test fun catalogRetainsOnlyPricedKnownVendors() {
        val data = """{"anthropic":{"models":{"claude-opus-5":{"cost":{"input":5,"output":25,"cache_read":0.5}},"x":{"name":"x"}}},"other":{"models":{"a":{"cost":{"input":1,"output":1}}}}}"""
        val table = PricingTable.fromModelsDev(data)!!
        assertEquals(0.5,table.price("anthropic","claude-opus-5")!!.cacheRead,0.0)
        assertNull(table.price("other","a"))
    }
}
