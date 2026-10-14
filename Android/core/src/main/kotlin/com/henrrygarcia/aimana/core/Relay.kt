@file:UseSerializers(IsoInstantSerializer::class)
package com.henrrygarcia.aimana.core

import java.time.Instant
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement

object IsoInstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

@Serializable data class UsageWindow(val kind: String, val usedPercent: Double, val windowMinutes: Int? = null, val resetsAt: Instant? = null) {
    val displayUsedPercent: Double get() = if (usedPercent.isFinite()) usedPercent.coerceIn(0.0, 100.0) else 0.0
    val remainingPercent: Double get() = 100 - displayUsedPercent
    fun isOutdated(now: Instant) = resetsAt?.let { !it.isAfter(now) } ?: false
    companion object {
        fun knownKind(kind: String) = kind in setOf("session", "weekly", "spend-limit", "free-requests", "monthly") ||
            (kind.startsWith("model:") && kind.length > 6) || (kind.startsWith("model-session:") && kind.length > 14)
    }
}
@Serializable data class TokenUsage(val input: Long = 0, val output: Long = 0, val cacheRead: Long = 0, val cacheWrite: Long = 0) {
    val total get() = input + output + cacheRead + cacheWrite
    operator fun plus(other: TokenUsage) = TokenUsage(input + other.input, output + other.output, cacheRead + other.cacheRead, cacheWrite + other.cacheWrite)
}
@Serializable data class ModelCost(val model: String, val tokens: TokenUsage = TokenUsage(), val usd: Double? = null)
@Serializable data class DailyCost(val day: String, val tokens: TokenUsage = TokenUsage(), val usd: Double = 0.0, val unpricedTokens: Long = 0, val models: List<ModelCost> = emptyList())
data class CostTotal(val usd: Double, val tokens: TokenUsage, val unpricedTokens: Long)
@Serializable data class CostReport(val providerID: String, val generatedAt: Instant, val days: List<DailyCost> = emptyList()) {
    fun total(lastDays: Int, endingOn: LocalDate): CostTotal {
        if (lastDays <= 0) return CostTotal(0.0, TokenUsage(), 0)
        val start = endingOn.minusDays(lastDays.toLong() - 1)
        val selected = days.filter { runCatching { LocalDate.parse(it.day) }.getOrNull()?.let { day -> !day.isBefore(start) && !day.isAfter(endingOn) } == true }
        return CostTotal(selected.sumOf { it.usd }, selected.fold(TokenUsage()) { a, b -> a + b.tokens }, selected.sumOf { it.unpricedTokens })
    }
    fun models(lastDays: Int, endingOn: LocalDate): List<ModelCost> {
        val start = endingOn.minusDays(lastDays.toLong() - 1)
        return days.filter { runCatching { LocalDate.parse(it.day) }.getOrNull()?.let { d -> !d.isBefore(start) && !d.isAfter(endingOn) } == true }
            .flatMap { it.models }.groupBy { it.model }.map { (name, items) ->
                ModelCost(name, items.fold(TokenUsage()) { a, b -> a + b.tokens }, if (items.any { it.usd == null }) null else items.sumOf { it.usd ?: 0.0 })
            }.sortedByDescending { it.usd ?: -1.0 }
    }
}
@Serializable data class HistoryPoint(val t: Instant, val used: Double, val resetsAt: Instant? = null)
@Serializable data class HistorySeries(val providerID: String, val kind: String, val points: List<HistoryPoint> = emptyList())
@Serializable data class UsageDetail(val kind: String, val remaining: Double = 0.0, val limit: Double? = null, val currency: String? = null, val used: Double? = null, val usable: Double? = null)
data class UsageInfo(val providerID: String, val providerName: String, val windows: List<UsageWindow>, val plan: String?, val lastUpdated: Instant,
                     val details: List<UsageDetail> = emptyList(), val cost: CostReport? = null, val history: List<HistorySeries> = emptyList(), val source: String? = null) {
    val primary get() = windows.firstOrNull { it.kind == "session" } ?: windows.firstOrNull { it.kind == "weekly" } ?: windows.firstOrNull()
    fun window(kind: String) = windows.firstOrNull { it.kind == kind }
}
data class RelayEntry(val providerID: String, val usage: UsageInfo?, val error: String?, val source: String?)
data class RelayEnvelope(val version: Int, val generatedAt: Instant, val entries: List<RelayEntry>, val costs: List<CostReport>, val history: List<HistorySeries>) {
    fun provider(id: String): Pair<UsageInfo?, String?> {
        val entry = entries.firstOrNull { it.providerID == id } ?: return null to "relayUnavailable"
        val usage = entry.usage ?: return null to (entry.error ?: "relayUnavailable")
        return usage.copy(cost = costs.firstOrNull { it.providerID == id } ?: usage.cost,
            history = history.filter { it.providerID == id }.ifEmpty { usage.history }, source = entry.source ?: usage.source) to null
    }
}
@Serializable private data class WireEnvelope(val version: Int, val generatedAt: Instant, val entries: List<WireEntry>, val costs: List<CostReport> = emptyList(), val history: List<HistorySeries> = emptyList())
@Serializable private data class WireEntry(val providerID: String, val usage: WireUsage? = null, val error: String? = null, val source: String? = null)
@Serializable private data class WireUsage(val providerID: String, val providerName: String, val windows: List<JsonElement>, val plan: String? = null,
    val lastUpdated: Instant, val details: List<JsonElement> = emptyList(), val cost: CostReport? = null, val history: List<HistorySeries> = emptyList(), val source: String? = null)
object RelayCodec {
    val json = Json { ignoreUnknownKeys = true; isLenient = false }
    fun decode(data: String): RelayEnvelope {
        val wire = json.decodeFromString<WireEnvelope>(data)
        require(wire.version == 1) { "Unsupported relay version" }
        return RelayEnvelope(wire.version, wire.generatedAt, wire.entries.map { entry ->
            val usage = entry.usage?.let { w -> UsageInfo(w.providerID, w.providerName,
                w.windows.mapNotNull { runCatching { json.decodeFromJsonElement<UsageWindow>(it) }.getOrNull()?.takeIf { win -> UsageWindow.knownKind(win.kind) } },
                w.plan, w.lastUpdated, w.details.mapNotNull { runCatching { json.decodeFromJsonElement<UsageDetail>(it) }.getOrNull() },
                w.cost, w.history, w.source) }
            RelayEntry(entry.providerID, usage, entry.error, entry.source?.takeIf { it in setOf("statusline", "logs", "endpoint") })
        }, wire.costs, wire.history.filter { UsageWindow.knownKind(it.kind) })
    }
}

private fun secondsBetween(start: Instant, end: Instant): Double {
    val duration = Duration.between(start, end)
    return duration.seconds.toDouble() + duration.nano / 1_000_000_000.0
}

enum class DisplayMode { USED, REMAINING;
    fun percent(window: UsageWindow) = if (this == USED) window.displayUsedPercent else window.remainingPercent
}
data class UsagePace(val status: Status, val expectedUsedPercent: Double, val projectedUsedAtReset: Double?, val exhaustsAt: Instant?) {
    enum class Status { TOO_EARLY, COMFORTABLE, FAST, DEPLETED }
    companion object {
        fun from(window: UsageWindow, now: Instant): UsagePace? {
            val minutes = window.windowMinutes?.takeIf { it > 0 } ?: return null
            val reset = window.resetsAt?.takeIf { it.isAfter(now) } ?: return null
            val total = minutes * 60.0
            val remaining = secondsBetween(now, reset).coerceIn(0.0, total)
            val elapsed = total - remaining
            val fraction = elapsed / total
            val used = window.displayUsedPercent
            val expected = fraction * 100
            if (used >= 100) return UsagePace(Status.DEPLETED, expected, null, null)
            if (fraction < 0.05 || elapsed < 300) return UsagePace(Status.TOO_EARLY, expected, null, null)
            val projected = used / fraction
            return if (projected > 105) UsagePace(Status.FAST, expected, projected,
                now.plusNanos(((100 - used) * elapsed / used * 1_000_000_000).roundToLong()))
            else UsagePace(Status.COMFORTABLE, expected, projected, null)
        }
    }
}
data class DailyBudget(val status: Status, val perDayPercent: Double, val daysLeft: Double, val remainingPercent: Double,
    val resetsAt: Instant, val usedToday: Double?, val todayBudgetPercent: Double?) {
    enum class Status { SPREAD, LAST_DAY, DEPLETED, OUTDATED }
    val todayFraction: Double? get() = if (usedToday != null && todayBudgetPercent != null && todayBudgetPercent > 0) usedToday / todayBudgetPercent else null
    companion object {
        fun from(window: UsageWindow, history: List<HistorySeries> = emptyList(), providerID: String? = null, now: Instant, zone: ZoneId = ZoneId.systemDefault()): DailyBudget? {
            val minutes = window.windowMinutes?.takeIf { it >= 2880 } ?: return null
            val reset = window.resetsAt ?: return null
            val remaining = window.remainingPercent
            if (!reset.isAfter(now)) return DailyBudget(Status.OUTDATED, 0.0, 0.0, remaining, reset, null, null)
            val days = secondsBetween(now, reset) / 86400.0
            val status = if (window.displayUsedPercent >= 100) Status.DEPLETED else if (days < 1) Status.LAST_DAY else Status.SPREAD
            val dayStart = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            val windowStart = reset.minusSeconds(minutes * 60L)
            val baseline = if (!windowStart.isBefore(dayStart)) 0.0 to windowStart else {
                history.filter { it.providerID == providerID && it.kind == window.kind }.flatMap { it.points }
                    .filter { it.resetsAt != null && abs(secondsBetween(it.resetsAt, reset)) <= 120 && !it.t.isAfter(dayStart) && !it.t.isBefore(dayStart.minus(12, ChronoUnit.HOURS)) && it.used.isFinite() }
                    .maxByOrNull { it.t }?.let { it.used.coerceIn(0.0, 100.0) to it.t }
            }
            val todayBudget = baseline?.let { (used, time) -> (100 - used) / max(1.0, secondsBetween(maxOf(time, dayStart), reset) / 86400.0) }
            return DailyBudget(status, if (status == Status.DEPLETED) 0.0 else remaining / max(1.0, days), days, remaining,
                reset, baseline?.let { max(0.0, window.displayUsedPercent - it.first) }, todayBudget)
        }
    }
}
data class ChartPoint(val time: Instant, val percent: Double)
data class Burndown(val start: Instant, val end: Instant, val actual: List<ChartPoint>, val guide: List<ChartPoint>,
    val projection: List<ChartPoint>, val current: ChartPoint?, val recordedPointCount: Int) {
    val hasEnoughHistory get() = recordedPointCount >= 2
    companion object {
        fun from(providerID: String, window: UsageWindow, history: List<HistorySeries>, mode: DisplayMode, observedAt: Instant): Burndown? {
            val minutes = window.windowMinutes?.takeIf { it > 0 } ?: return null
            val end = window.resetsAt ?: return null
            val start = end.minusSeconds(minutes * 60L)
            fun displayed(used: Double): Double { val safe = if (used.isFinite()) used.coerceIn(0.0, 100.0) else 0.0; return if (mode == DisplayMode.USED) safe else 100 - safe }
            val matched = history.filter { it.providerID == providerID && it.kind == window.kind }.flatMap { it.points }
                .filter { it.resetsAt != null && abs(secondsBetween(it.resetsAt, end)) <= 120 && !it.t.isBefore(start) && !it.t.isAfter(end) && it.used.isFinite() }
                .sortedBy { it.t }
            val actual = matched.map { ChartPoint(it.t, displayed(it.used)) }.toMutableList()
            val snapshot = if (!observedAt.isBefore(start) && !observedAt.isAfter(end)) ChartPoint(observedAt, mode.percent(window)) else null
            if (snapshot != null && actual.isNotEmpty() && actual.last().time.isBefore(observedAt.minusSeconds(1))) actual.add(snapshot)
            val pace = snapshot?.let { UsagePace.from(window, observedAt) }
            val projection = if (snapshot != null && pace?.projectedUsedAtReset != null) buildList {
                add(snapshot)
                pace.exhaustsAt?.takeIf { it.isAfter(observedAt) && it.isBefore(end) }?.let { add(ChartPoint(it, displayed(100.0))) }
                add(ChartPoint(end, displayed(pace.projectedUsedAtReset)))
            } else emptyList()
            return Burndown(start, end, actual, listOf(ChartPoint(start, displayed(0.0)), ChartPoint(end, displayed(100.0))),
                projection, snapshot ?: actual.lastOrNull(), matched.size)
        }
    }
}
