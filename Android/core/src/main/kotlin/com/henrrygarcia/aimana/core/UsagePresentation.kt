package com.henrrygarcia.aimana.core

import java.time.Instant

/** The status shown by iOS UsageCard, derived from the shared pace and remaining-quota rules. */
enum class QuotaStatus { AVAILABLE, ON_PACE, FAST, LOW, CRITICAL, DEPLETED, STALE }

fun quotaStatus(window: UsageWindow, lastUpdated: Instant, now: Instant): QuotaStatus {
    if (window.isOutdated(now) || lastUpdated.isBefore(now.minusSeconds(3600))) return QuotaStatus.STALE
    val pace = UsagePace.from(window, now)
    if (pace?.status == UsagePace.Status.DEPLETED) return QuotaStatus.DEPLETED
    if (pace?.status == UsagePace.Status.FAST) return QuotaStatus.FAST
    if (pace?.status == UsagePace.Status.COMFORTABLE && (pace.projectedUsedAtReset ?: 0.0) >= 1.0) return QuotaStatus.ON_PACE
    return when {
        window.remainingPercent < 10 -> QuotaStatus.CRITICAL
        window.remainingPercent < 20 -> QuotaStatus.LOW
        else -> QuotaStatus.AVAILABLE
    }
}

/** Why an old reading is old, when it can be told: the computer stopped publishing, or the CLI was not used since. */
enum class StaleReason { PUBLISHER_SILENT, NO_RECENT_USE }

fun staleReason(usage: UsageInfo, now: Instant): StaleReason? {
    val hour = now.minusSeconds(3600)
    if (!usage.lastUpdated.isBefore(hour)) return null
    val published = usage.relayPublishedAt ?: return null
    return when {
        published.isBefore(hour) -> StaleReason.PUBLISHER_SILENT
        // Endpoint readings refresh on every publish; these only change when the CLI writes something new.
        usage.source == "statusline" || usage.source == "logs" -> StaleReason.NO_RECENT_USE
        else -> null
    }
}

fun demoCostTokenTotals(now: Instant = Instant.now(), zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): Map<String, Long> =
    DemoData.envelope(now, zone).costs.associate { it.providerID to it.total(7, now.atZone(zone).toLocalDate()).tokens.total }
