package com.henrrygarcia.aimana.core.net

import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/// When a 429 lets us try again: `Retry-After` in seconds or as an HTTP date, otherwise a minute.
object RetryAfter {
    fun until(headers: Map<String, String>, now: Instant, fallbackSeconds: Long = 60): Instant {
        val raw = headers.entries.firstOrNull { it.key.equals("Retry-After", ignoreCase = true) }?.value?.trim()
        if (raw.isNullOrEmpty()) return now.plusSeconds(fallbackSeconds)
        raw.toLongOrNull()?.takeIf { it >= 0 }?.let { return now.plusSeconds(it) }
        return runCatching { ZonedDateTime.parse(raw, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant() }
            .getOrElse { now.plusSeconds(fallbackSeconds) }
    }
}
