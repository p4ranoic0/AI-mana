package com.henrrygarcia.aimana.core

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Prices are USD per million tokens, scoped to a vendor. */
data class ModelPrice(val input: Double, val output: Double, val cacheRead: Double = 0.0, val cacheWrite: Double = 0.0) {
    fun cost(tokens: TokenUsage) = (tokens.input * input + tokens.output * output + tokens.cacheRead * cacheRead + tokens.cacheWrite * cacheWrite) / 1_000_000.0
}
data class PricingTable(val prices: Map<String, ModelPrice>) {
    fun price(provider: String, model: String): ModelPrice? {
        val candidates = listOf(model, model.substringBefore('['))
        for (candidate in candidates) {
            prices["$provider/$candidate"]?.let { return it }
            prices["$provider/${candidate.replace(Regex("-\\d{8}$"), "")}"]?.let { return it }
        }
        return null
    }
    companion object {
        fun fromModelsDev(data: String): PricingTable? {
            val root = runCatching { Json.parseToJsonElement(data).jsonObject }.getOrNull() ?: return null
            val prices = mutableMapOf<String, ModelPrice>()
            for (vendor in listOf("anthropic", "openai")) {
                val models = root[vendor]?.jsonObject?.get("models")?.jsonObject ?: continue
                for ((id, value) in models) {
                    val cost = value.jsonObject["cost"]?.jsonObject ?: continue
                    val input = cost["input"]?.jsonPrimitive?.doubleOrNull ?: continue
                    val output = cost["output"]?.jsonPrimitive?.doubleOrNull ?: continue
                    prices["$vendor/$id"] = ModelPrice(input, output, cost["cache_read"]?.jsonPrimitive?.doubleOrNull ?: 0.0, cost["cache_write"]?.jsonPrimitive?.doubleOrNull ?: 0.0)
                }
            }
            return prices.takeIf { it.isNotEmpty() }?.let(::PricingTable)
        }
    }
}
data class CostEvent(val key: String, val timestamp: Instant, val model: String, val tokens: TokenUsage)
class CostAggregator(private val priceProvider: String, private val pricing: PricingTable, private val zone: ZoneId = ZoneId.systemDefault()) {
    private val events = mutableMapOf<String, CostEvent>()
    fun add(event: CostEvent) { if ((events[event.key]?.tokens?.output ?: -1) < event.tokens.output) events[event.key] = event }
    fun report(providerID: String, now: Instant, days: Int): CostReport {
        val cutoff = now.atZone(zone).toLocalDate().minusDays((days.coerceAtLeast(1) - 1).toLong())
        val grouped = events.values.groupBy { it.timestamp.atZone(zone).toLocalDate() }.filterKeys { !it.isBefore(cutoff) }
        val built = grouped.toSortedMap().map { (day, events) ->
            val models = events.groupBy { it.model }.map { (model, rows) ->
                val tokens = rows.fold(TokenUsage()) { sum, row -> sum + row.tokens }
                ModelCost(model, tokens, pricing.price(priceProvider, model)?.cost(tokens))
            }.sortedByDescending { it.usd ?: -1.0 }
            DailyCost(day.toString(), models.fold(TokenUsage()) { sum, model -> sum + model.tokens },
                models.sumOf { it.usd ?: 0.0 }, models.filter { it.usd == null }.sumOf { it.tokens.total }, models)
        }
        return CostReport(providerID, now, built)
    }
}
