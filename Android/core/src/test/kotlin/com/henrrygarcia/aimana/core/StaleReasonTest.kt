package com.henrrygarcia.aimana.core

import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StaleReasonTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")
    private fun ago(minutes: Long) = now.minus(Duration.ofMinutes(minutes))
    private fun usage(updated: Instant, source: String?) =
        UsageInfo("claude", "Claude Code", listOf(UsageWindow("session", 40.0)), null, updated, source = source)
    private fun relay(published: Instant, updated: Instant, source: String?) =
        RelayEnvelope(1, published, listOf(RelayEntry("claude", usage(updated, null), null, source)), emptyList(), emptyList())

    @Test fun relayReadingsKnowWhenTheComputerPublished() {
        assertEquals(ago(5), relay(ago(5), ago(90), "logs").provider("claude").first?.relayPublishedAt)
    }

    @Test fun freshReadingHasNoReason() {
        assertNull(staleReason(relay(ago(5), ago(30), "endpoint").provider("claude").first!!, now))
    }

    @Test fun computerThatStoppedPublishingIsTheReason() {
        // Whatever the source: the relay itself is old.
        assertEquals(StaleReason.PUBLISHER_SILENT, staleReason(relay(ago(180), ago(180), "endpoint").provider("claude").first!!, now))
        assertEquals(StaleReason.PUBLISHER_SILENT, staleReason(relay(ago(120), ago(300), "logs").provider("claude").first!!, now))
    }

    @Test fun localSourcesWaitForTheNextUse() {
        // The computer publishes, but the CLI has not written anything new: nothing is broken.
        assertEquals(StaleReason.NO_RECENT_USE, staleReason(relay(ago(5), ago(240), "statusline").provider("claude").first!!, now))
        assertEquals(StaleReason.NO_RECENT_USE, staleReason(relay(ago(5), ago(240), "logs").provider("claude").first!!, now))
    }

    @Test fun unknownCausesStayGeneric() {
        // Endpoint readings refresh on every publish, so a fresh relay with an old one has no known cause.
        assertNull(staleReason(relay(ago(5), ago(240), "endpoint").provider("claude").first!!, now))
        // Readings that did not come through the relay (direct access, demo) carry no publish time.
        assertNull(staleReason(usage(ago(240), null), now))
    }
}
