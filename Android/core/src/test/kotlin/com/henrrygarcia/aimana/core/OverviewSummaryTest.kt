package com.henrrygarcia.aimana.core

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class OverviewSummaryTest {
    private val now = Instant.parse("2026-10-04T12:00:00Z")
    private fun usage(id: String, session: Double, weekly: Double) = UsageInfo(id,id,listOf(UsageWindow("session",session),UsageWindow("weekly",weekly)),null,now)
    @Test fun usedHighlightsHighestAndRemainingLowest() {
        val usages = listOf(usage("claude",18.0,42.0),usage("codex",33.0,61.0))
        val used = OverviewSummary.from(usages,DisplayMode.USED)!!
        assertEquals(4,used.lanes.size)
        assertEquals("codex",used.highlighted.providerID)
        assertEquals("weekly",used.highlighted.window.kind)
        val remaining = OverviewSummary.from(usages,DisplayMode.REMAINING)!!
        assertEquals(39.0,remaining.highlighted.displayPercent,0.0)
    }
    @Test fun emptyReadingsYieldNoSummary() { assertNull(OverviewSummary.from(emptyList(),DisplayMode.USED)) }
}
