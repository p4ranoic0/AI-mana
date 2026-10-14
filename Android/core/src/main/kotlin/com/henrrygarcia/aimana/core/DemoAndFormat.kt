package com.henrrygarcia.aimana.core

import java.time.Instant
import java.time.ZoneId
import java.text.NumberFormat
import java.util.Locale
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

object UsageFormat {
    fun percent(value: Double, locale: Locale = Locale.getDefault()) = NumberFormat.getIntegerInstance(locale).format(value.roundToInt()) + "%"
    fun relative(updated: Instant, now: Instant = Instant.now()): String {
        val seconds = (now.epochSecond - updated.epochSecond).coerceAtLeast(0)
        return when { seconds < 60 -> "now"; seconds < 3600 -> "${seconds / 60}m"; seconds < 86400 -> "${seconds / 3600}h"; else -> "${seconds / 86400}d" }
    }
    fun countdown(reset: Instant?, now: Instant = Instant.now()): String {
        if (reset == null) return ""
        val seconds = (reset.epochSecond - now.epochSecond).coerceAtLeast(0)
        val days = seconds / 86400; val hours = (seconds % 86400) / 3600; val minutes = (seconds % 3600) / 60
        return if (days > 0) "${days}d ${hours}h" else if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
    }
    fun money(value: Double, locale: Locale = Locale.getDefault()): String = NumberFormat.getCurrencyInstance(locale).apply { currency = java.util.Currency.getInstance("USD") }.format(value)
    fun moneyDisplay(value: Double, locale: Locale = Locale.getDefault()): String = NumberFormat.getCurrencyInstance(locale).apply {
        currency = java.util.Currency.getInstance("USD")
        minimumFractionDigits = if (kotlin.math.abs(value) >= 1000) 0 else 2
        maximumFractionDigits = if (kotlin.math.abs(value) >= 1000) 0 else 2
        roundingMode = java.math.RoundingMode.HALF_UP
    }.format(if (value.isFinite()) value else 0.0)
    fun tokenCount(count: Long, locale: Locale = Locale.getDefault()): String {
        val formatter = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 0
            maximumFractionDigits = if (count >= 100_000_000L) 0 else 1
        }
        return when {
            count >= 1_000_000L -> "${formatter.format(count / 1_000_000.0)} M"
            count >= 1_000L -> "${formatter.format(count / 1_000.0)} k"
            else -> NumberFormat.getIntegerInstance(locale).format(count)
        }
    }
}
object DemoData {
    val referenceTime: Instant = Instant.parse("2026-10-13T18:00:00Z")
    val demoZone: ZoneId = ZoneId.of("America/Lima")
    fun envelope(now: Instant = referenceTime, zone: ZoneId = demoZone): RelayEnvelope {
        val providers = listOf(
            usage("claude", "Claude Code", "Max", 18.0, 42.0, now.plusSeconds(3 * 3600 + 15 * 60), now.plusSeconds(4 * 86400 + 3600), "statusline", now, zone, sessionGain = 11.0,
                extra = 7.5, extraKind = "model:Sonnet", details = listOf(UsageDetail("extraUsage", 15.66, 20.0, "USD", 4.34))),
            usage("codex", "OpenAI Codex", "Pro", 33.0, 61.0, now.plusSeconds(5 * 3600 + 22 * 60), now.plusSeconds(2 * 86400 + 7200), "logs", now, zone, sessionGain = 22.0,
                extra = 12.0, extraKind = "model-session:GPT-5.3-Codex-Spark", secondExtra = 27.0, secondExtraKind = "model:GPT-5.3-Codex-Spark")
        )
        val costs = providers.map { provider ->
            val base = if (provider.providerID == "claude") 2.35 else 1.72
            val first = if (provider.providerID == "claude") "Claude Sonnet 4.5" else "GPT-5.3-Codex"
            val second = if (provider.providerID == "claude") "Claude Opus 4.1" else "GPT-5.3-Codex-Spark"
            val today = now.atZone(zone).toLocalDate()
            CostReport(provider.providerID, now, (29 downTo 0).map { offset ->
                val usd = if (offset == 0) base else base * (0.5 + offset % 5 * 0.12)
                val a = ModelCost(first, TokenUsage(42000, 8000, 110000), usd * 0.8)
                val b = ModelCost(second, TokenUsage(9000, 2000), usd * 0.2)
                DailyCost(today.minusDays(offset.toLong()).toString(), a.tokens + b.tokens, usd, 0, listOf(a, b))
            })
        }
        return RelayEnvelope(1, now, providers.map { RelayEntry(it.providerID, it, null, it.source) }, costs, providers.flatMap { it.history })
    }
    private fun usage(id: String, name: String, plan: String, session: Double, weekly: Double, sessionReset: Instant, weekReset: Instant, source: String, now: Instant, zone: ZoneId, sessionGain: Double,
                      extra: Double? = null, extraKind: String? = null, secondExtra: Double? = null, secondExtraKind: String? = null,
                      details: List<UsageDetail> = emptyList()): UsageInfo {
        val windows = listOfNotNull(UsageWindow("session", session, 300, sessionReset), UsageWindow("weekly", weekly, 10080, weekReset),
            extra?.let { UsageWindow(extraKind!!, it, if (extraKind.startsWith("model-session:")) 300 else 10080, if (extraKind.startsWith("model-session:")) sessionReset else weekReset) },
            secondExtra?.let { UsageWindow(secondExtraKind!!, it, 10080, weekReset) })
        val weeklyWindow = windows.first { it.kind == "weekly" }
        val weeklyReset = weeklyWindow.resetsAt!!
        val start = maxOf(weeklyReset.minusSeconds(weeklyWindow.windowMinutes!! * 60L), now.minusSeconds(7 * 86400L))
        val times = generateSequence(start) { it.plusSeconds(20 * 60L) }.takeWhile { it.isBefore(now) }.toList()
        fun activity(time: Instant): Double {
            val local = time.atZone(zone)
            val day = local.toLocalDate().toEpochDay() + 719163L
            return when (local.hour) {
                in 10..12 -> 1.0 + (day % 3) * 0.2
                in 14..17 -> 1.6 + (day % 2) * 0.5
                in 21..22 -> if (day % 2 == 0L) 0.7 else 0.0
                else -> 0.0
            }
        }
        val raw = times.map(::activity)
        val scale = weeklyWindow.displayUsedPercent / raw.sum().coerceAtLeast(0.001)
        val weeklyPoints = mutableListOf<HistoryPoint>()
        val sessionPoints = mutableListOf<HistoryPoint>()
        var used = 0.0
        var sessionUsed = 0.0
        var sessionReset: Instant? = null
        for ((time, act) in times.zip(raw)) {
            used += act * scale
            if (act > 0) {
                if (sessionReset == null || !time.isBefore(sessionReset)) {
                    sessionReset = time.plusSeconds(5 * 3600L)
                    sessionUsed = 0.0
                }
                sessionUsed = (sessionUsed + act * scale * sessionGain).coerceAtMost(100.0)
            }
            weeklyPoints += HistoryPoint(time, used, weeklyReset)
            val reset = sessionReset
            if (reset != null && time.isBefore(reset)) sessionPoints += HistoryPoint(time, sessionUsed, reset)
        }
        val history = listOf(HistorySeries(id, "weekly", weeklyPoints), HistorySeries(id, "session", sessionPoints))
        return UsageInfo(id, name, windows, plan, now, details = details, history = history, source = source)
    }
}
