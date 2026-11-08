package com.henrrygarcia.aimana.core.net

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class RetryAfterTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")

    @Test fun retryAfterSeconds() = assertEquals(now.plusSeconds(120), RetryAfter.until(mapOf("Retry-After" to "120"), now))
    @Test fun retryAfterIsCaseInsensitive() = assertEquals(now.plusSeconds(30), RetryAfter.until(mapOf("retry-after" to " 30 "), now))
    @Test fun retryAfterHttpDate() = assertEquals(Instant.parse("2027-01-15T08:10:00Z"),
        RetryAfter.until(mapOf("Retry-After" to "Fri, 15 Jan 2027 08:10:00 GMT"), now))
    @Test fun retryAfterMissingFallsBack60() = assertEquals(now.plusSeconds(60), RetryAfter.until(emptyMap(), now))
    @Test fun retryAfterGarbageFallsBack60() = assertEquals(now.plusSeconds(60), RetryAfter.until(mapOf("Retry-After" to "soon"), now))
}
