package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.InMemoryCredentialStore
import java.time.Duration
import java.time.Instant
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class SessionKeeperTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val store = InMemoryCredentialStore()
    private fun session(refresh: String, expires: Instant) = ClaudeSession("A-$refresh", refresh, expires)

    private fun keeper(renew: suspend (ClaudeSession, Instant) -> ClaudeSession) =
        SessionKeeper("k", store, { now }, Duration.ofSeconds(120), ClaudeSessionCodec, renew)

    @Test fun concurrentCallersShareOneRenewal() = runBlocking {
        val renewals = AtomicInteger()
        val k = keeper { old, _ -> renewals.incrementAndGet(); delay(50); session("R2", old.expiresAt.plusSeconds(3600)) }
        k.save(session("R1", now.minusSeconds(5)))
        val results = (1..5).map { async { k.current() } }.awaitAll()
        assertEquals(1, renewals.get())
        assertEquals(setOf("R2"), results.map { it.refreshToken }.toSet())
    }

    @Test fun concurrentCallersShareOneFailedRenewal() = runBlocking {
        val renewals = AtomicInteger()
        val k = keeper { _, _ -> renewals.incrementAndGet(); delay(50); throw UsageError.RateLimited(now.plusSeconds(60)) }
        k.save(session("R1", now.minusSeconds(5)))
        val errors = (1..5).map { async { runCatching { k.current() }.exceptionOrNull() } }.awaitAll()
        assertEquals(1, renewals.get())   // waiters get the same failure instead of asking again
        assertEquals(setOf<Throwable?>(UsageError.RateLimited(now.plusSeconds(60))), errors.toSet())
        // A later, separate call may try again.
        runCatching { k.current() }
        assertEquals(2, renewals.get())
    }

    @Test fun cancelledCallerStillPersistsTheRotatedToken() = runBlocking {
        val k = keeper { old, _ -> delay(100); session("R2", old.expiresAt.plusSeconds(3600)) }
        k.save(session("R1", now.minusSeconds(5)))
        val call = async { k.current() }
        delay(30)
        call.cancel()   // e.g. the screen went away mid-request: R1 was already redeemed
        delay(150)
        assertEquals("R2", k.load()!!.refreshToken)
    }

    @Test fun rotatedTokenPersistedBeforeUse() = runBlocking {
        val k = keeper { old, _ -> session("R2", old.expiresAt.plusSeconds(3600)) }
        k.save(session("R1", now.minusSeconds(5)))
        k.current()
        assertEquals("R2", k.load()!!.refreshToken)
    }

    @Test fun renewDoesNotOverwriteNewerSignIn() = runBlocking {
        val k = keeper { old, _ ->
            store.write(ClaudeSessionCodec.encode(session("NEW", now.plusSeconds(3600))), "k")   // a sign-in meanwhile
            session("RENEWED", old.expiresAt.plusSeconds(3600))
        }
        k.save(session("OLD", now.minusSeconds(5)))
        assertEquals("NEW", k.current().refreshToken)
        assertEquals("NEW", k.load()!!.refreshToken)
    }

    @Test fun signInDuringRenewalWaitsAndWins() = runBlocking {
        val events = Collections.synchronizedList(mutableListOf<String>())
        val k = keeper { old, _ -> events += "renew-start"; delay(150); events += "renew-end"; session("RENEWED", old.expiresAt.plusSeconds(3600)) }
        k.save(session("OLD", now.minusSeconds(5)))
        val renewed = async { k.current() }
        delay(50)
        k.save(session("NEW", now.plusSeconds(3600)))
        events += "saved"
        renewed.await()
        assertEquals(listOf("renew-start", "renew-end", "saved"), events)
        assertEquals("NEW", k.load()!!.refreshToken)
    }

    @Test fun signOutDuringRenewalStaysSignedOut() = runBlocking {
        val k = keeper { old, _ -> delay(150); session("RENEWED", old.expiresAt.plusSeconds(3600)) }
        k.save(session("OLD", now.minusSeconds(5)))
        val renewed = async { runCatching { k.current() } }
        delay(50)
        k.delete()
        renewed.await()
        assertNull(k.load())
    }

    @Test fun invalidGrantLooksOnceMoreBeforeGivingUp() = runBlocking {
        val calls = AtomicInteger()
        val k = keeper { old, _ ->
            if (calls.incrementAndGet() == 1) {
                // Another process rotated the token first: our redeem fails, but the store already has a newer one.
                store.write(ClaudeSessionCodec.encode(session("ROTATED", now.minusSeconds(1))), "k")
                throw UsageError.Unauthenticated
            }
            session("AFTER", old.expiresAt.plusSeconds(3600))
        }
        k.save(session("OLD", now.minusSeconds(5)))
        assertEquals("AFTER", k.current().refreshToken)
    }

    @Test fun noSessionIsUnauthenticated() = runBlocking {
        try { keeper { o, _ -> o }.current(); fail() } catch (e: UsageError) { assertEquals(UsageError.Unauthenticated, e) }
    }
}
