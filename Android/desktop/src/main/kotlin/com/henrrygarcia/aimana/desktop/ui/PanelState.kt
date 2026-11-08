package com.henrrygarcia.aimana.desktop.ui

import com.henrrygarcia.aimana.core.ProviderState
import com.henrrygarcia.aimana.core.StaleReason
import com.henrrygarcia.aimana.core.staleReason
import com.henrrygarcia.aimana.core.providers.UsageError
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

data class LaneRow(val title: String, val percent: String, val reset: String?)

/// One provider in the panel. `headline` is null when there is no reading: the panel never shows 0 % for missing data.
data class PanelRow(val providerID: String, val name: String, val headline: String?, val lanes: List<LaneRow>, val message: String?,
                    val details: List<String> = emptyList(), val cost: String? = null, val asOf: String? = null)

fun panelRows(states: List<ProviderState>, strings: Strings, now: Instant, zone: ZoneId = ZoneId.systemDefault()): List<PanelRow> =
    states.map { state ->
        val name = if (state.providerID == "claude") "Claude Code" else "OpenAI Codex"
        val current = state.usage?.windows.orEmpty().filter { !it.isOutdated(now) }
        val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(java.util.Locale.getDefault()).withZone(zone)
        val lanes = current.map { window ->
            LaneRow(laneTitle(window.kind, strings), "${window.displayUsedPercent.roundToInt()}%", window.resetsAt?.let { time.format(it) })
        }
        val headline = current.maxByOrNull { it.displayUsedPercent }?.let { "${it.displayUsedPercent.roundToInt()}%" }
        val error = state.error?.let { errorText(it, state.providerID, strings, time) }
        val details = state.usage?.details.orEmpty().mapNotNull { detailText(it, strings) }
        val cost = state.usage?.cost?.total(7, java.time.LocalDate.now(zone))?.takeIf { it.usd > 0 }
            ?.let { strings.format("panel.cost7", money(it.usd, "USD", strings)) }
        val stale = state.usage?.let { usage ->
            when (staleReason(usage, now)) {
                StaleReason.PUBLISHER_SILENT -> strings.format("stale.publisher", elapsed(usage.relayPublishedAt!!, now))
                StaleReason.NO_RECENT_USE -> strings["stale.noRecentUse"]
                null -> null
            }
        }
        val message = when {
            state.isFallback && error != null -> strings.format("panel.fallback", error)
            error != null -> error
            stale != null -> stale
            headline == null && details.isEmpty() -> strings["panel.noData"]
            else -> null
        }
        PanelRow(state.providerID, name, headline, lanes, message, details, cost,
                 state.usage?.let { strings.format("panel.asOf", age(it.lastUpdated, now, zone, strings)) })
    }

/// "45m", "3h", "2d": how long ago.
private fun elapsed(since: Instant, now: Instant): String {
    val seconds = (now.epochSecond - since.epochSecond).coerceAtLeast(0)
    return when { seconds < 3600 -> "${seconds / 60}m"; seconds < 86_400 -> "${seconds / 3600}h"; else -> "${seconds / 86_400}d" }
}

/// When the reading was taken: the time today, otherwise the date too.
private fun age(at: Instant, now: Instant, zone: ZoneId, strings: Strings): String {
    val sameDay = at.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()
    val pattern = if (sameDay) "HH:mm" else "MMM d, HH:mm"
    return DateTimeFormatter.ofPattern(pattern, strings.locale).withZone(zone).format(at)
}

private fun money(amount: Double, currency: String?, strings: Strings): String =
    java.text.NumberFormat.getCurrencyInstance(strings.locale).apply {
        runCatching { this.currency = java.util.Currency.getInstance(currency ?: "USD") }
    }.format(amount)

/// Credits and paid usage that come with the quota (same kinds as the Apple app).
private fun detailText(detail: com.henrrygarcia.aimana.core.UsageDetail, strings: Strings): String? = when (detail.kind) {
    "cloudCredits" -> detail.limit?.let { strings.format("detail.cloudCredits", money(detail.remaining, detail.currency, strings), money(it, detail.currency, strings)) }
    "extraUsage" -> detail.used?.let { used ->
        detail.limit?.let { strings.format("detail.extraUsage", money(used, detail.currency, strings), money(it, detail.currency, strings)) }
            ?: strings.format("detail.extraUsageNoCap", money(used, detail.currency, strings))
    }
    "creditBalance" -> strings.format("detail.creditBalance", money(detail.remaining, detail.currency, strings))
    "resetCredits" -> strings.format("detail.resetCredits", detail.remaining.toInt())
    else -> null
}

private fun laneTitle(kind: String, strings: Strings): String = when {
    kind == "session" -> strings["lane.session"]
    kind == "weekly" -> strings["lane.weekly"]
    kind.startsWith("model-session:") -> kind.removePrefix("model-session:")
    kind.startsWith("model:") -> kind.removePrefix("model:")
    else -> kind
}

private fun errorText(error: UsageError, providerID: String, strings: Strings, time: DateTimeFormatter): String = when (error) {
    UsageError.Unauthenticated -> strings[if (providerID == "claude") "error.unauthenticated.claude" else "error.unauthenticated.codex"]
    is UsageError.RateLimited -> error.until?.let { strings.format("error.rateLimited", time.format(it)) } ?: strings["error.rateLimitedNow"]
    UsageError.Decoding -> strings["error.decoding"]
    UsageError.Network -> strings["error.network"]
    is UsageError.Server -> strings.format("error.server", error.status)
    UsageError.RelayUnavailable -> strings["error.relayUnavailable"]
    UsageError.UnsupportedCredentialStore -> strings["error.keyring"]
}
