package com.henrrygarcia.aimana.core.net

import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BackoffGateTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")

    @Test fun blockSurvivesNewInstance() {
        val store = InMemoryKeyValueStore()
        BackoffGate.shared("claude", store).block(now.plusSeconds(600))
        assertEquals(now.plusSeconds(600), BackoffGate.shared("claude", store).check(now.plusSeconds(10)))
    }

    @Test fun earlierInstanceSeesALaterBlockFromAnother() {
        val store = InMemoryKeyValueStore()
        val app = BackoffGate.shared("claude", store)
        app.block(now.plusSeconds(60))
        BackoffGate.shared("claude", store).block(now.plusSeconds(600))
        assertEquals(now.plusSeconds(600), app.check(now.plusSeconds(120)))
    }

    @Test fun anEarlierBlockNeverShortensALaterOne() {
        val store = InMemoryKeyValueStore()
        BackoffGate.shared("claude", store).block(now.plusSeconds(600))
        val other = BackoffGate.shared("claude", store)
        other.block(now.plusSeconds(60))
        assertEquals(now.plusSeconds(600), BackoffGate.shared("claude", store).check(now.plusSeconds(120)))
    }

    @Test fun expiredBlockClears() {
        val store = InMemoryKeyValueStore()
        BackoffGate.shared("codex", store).block(now.plusSeconds(5))
        assertNull(BackoffGate.shared("codex", store).check(now.plusSeconds(6)))
    }

    @Test fun inMemoryGateStaysInMemory() {
        BackoffGate().block(now.plusSeconds(600))
        assertNull(BackoffGate().check(now))
    }
}
