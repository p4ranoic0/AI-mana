package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.providers.UsageError
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectAndRelayTest {
    private val t = Instant.parse("2027-01-10T00:00:00Z")
    private val report = CostReport("claude", t)
    private fun usage(used: Double, cost: CostReport? = null, plan: String? = null) =
        UsageInfo("claude", "Claude Code", listOf(UsageWindow("session", used, 300)), plan, t, cost = cost)

    @Test fun directWinsAndBorrowsRelayCosts() = runBlocking {
        val state = DirectAndRelay({ usage(10.0) }, { usage(99.0, report, "max") }, { true }).state("claude")
        assertEquals(10.0, state.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(report, state.usage!!.cost)
        assertEquals("max", state.usage!!.plan)
        assertNull(state.error)
        assertFalse(state.isFallback)
    }

    @Test fun directFailsWithRelayIsFallbackWithError() = runBlocking {
        val state = DirectAndRelay({ throw UsageError.Unauthenticated }, { usage(42.0) }, { true }).state("claude")
        assertEquals(42.0, state.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(UsageError.Unauthenticated, state.error)
        assertTrue(state.isFallback)
    }

    @Test fun directFailsWithoutRelayKeepsError() = runBlocking {
        val state = DirectAndRelay({ throw UsageError.Server(500) }, { null }, { true }).state("claude")
        assertNull(state.usage)
        assertEquals(UsageError.Server(500), state.error)
        assertFalse(state.isFallback)
    }

    @Test fun offUsesRelayOnly() = runBlocking {
        val calls = AtomicInteger()
        val state = DirectAndRelay({ calls.incrementAndGet(); usage(10.0) }, { usage(7.0) }, { false }).state("claude")
        assertEquals(7.0, state.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(0, calls.get())
        assertEquals(UsageError.RelayUnavailable, DirectAndRelay({ usage(1.0) }, { null }, { false }).state("claude").error)
    }

    @Test fun revokedWhileInFlightDiscardsDirect() = runBlocking {
        val checks = AtomicInteger()
        val state = DirectAndRelay({ usage(10.0) }, { usage(42.0) }, { checks.incrementAndGet() == 1 }).state("claude")
        assertEquals(42.0, state.usage!!.primary!!.usedPercent, 0.0)
        assertFalse(state.isFallback)
    }

    @Test fun failureAfterRevocationIsPlainRelayNotADirectError() = runBlocking {
        var on = true
        val state = DirectAndRelay({ on = false; throw UsageError.RelayUnavailable }, { usage(42.0) }, { on }).state("claude")
        assertEquals(42.0, state.usage!!.primary!!.usedPercent, 0.0)
        assertNull(state.error)
        assertFalse(state.isFallback)
    }

    @Test fun unexpectedFailureIsNetwork() = runBlocking {
        val state = DirectAndRelay({ throw IllegalStateException("boom") }, { usage(42.0) }, { true }).state("claude")
        assertEquals(UsageError.Network, state.error)
        assertTrue(state.isFallback)
    }
}
