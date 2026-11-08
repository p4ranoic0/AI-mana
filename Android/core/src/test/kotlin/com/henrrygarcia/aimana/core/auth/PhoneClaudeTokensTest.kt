package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.providers.MockTransport
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.providers.reply
import com.henrrygarcia.aimana.core.storage.InMemoryCredentialStore
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PhoneClaudeTokensTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val store = InMemoryCredentialStore()
    private fun stored(s: ClaudeSession) = store.write(ClaudeSessionCodec.encode(s), PhoneClaudeTokens.STORE_KEY)

    @Test fun noSessionIsUnauthenticated() = runBlocking {
        val tokens = PhoneClaudeTokens(store, MockTransport(mutableListOf()), { now })
        assertFalse(tokens.isSignedIn)
        try { tokens.credentials(); fail() } catch (e: UsageError) { assertEquals(UsageError.Unauthenticated, e) }
    }

    @Test fun freshSessionIsUsedAsIs() = runBlocking {
        stored(ClaudeSession("A", "R", now.plusSeconds(3600)))
        val transport = MockTransport(mutableListOf())
        assertEquals("A", PhoneClaudeTokens(store, transport, { now }).credentials().token)
        assertTrue(transport.requests.isEmpty())
    }

    @Test fun expiringSessionRenewsAndPersists() = runBlocking {
        stored(ClaudeSession("A", "R", now.plusSeconds(60)))      // inside the 120 s margin
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"A2","refresh_token":"R2","expires_in":3600}""")))
        val tokens = PhoneClaudeTokens(store, transport, { now })
        assertEquals("A2", tokens.credentials().token)
        assertEquals("R2", ClaudeSessionCodec.decode(store.read(PhoneClaudeTokens.STORE_KEY)!!)!!.refreshToken)
    }

    @Test fun signOutForgetsTheSession() = runBlocking {
        stored(ClaudeSession("A", "R", now.plusSeconds(3600)))
        val tokens = PhoneClaudeTokens(store, MockTransport(mutableListOf()), { now })
        assertTrue(tokens.isSignedIn)
        tokens.signOut()
        assertFalse(tokens.isSignedIn)
    }
}
