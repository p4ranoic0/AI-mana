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

fun demoCostTokenTotals(now: Instant = Instant.now(), zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): Map<String, Long> =
    DemoData.envelope(now, zone).costs.associate { it.providerID to it.total(7, now.atZone(zone).toLocalDate()).tokens.total }
