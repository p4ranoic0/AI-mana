package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectAccessConsentTest {
    @Test fun offByDefault() {
        val consent = DirectAccessConsent(InMemoryKeyValueStore())
        for (provider in DirectProvider.entries) {
            assertFalse(consent.isGranted(provider))
            assertNull(consent.consentedAt(provider))
        }
    }

    @Test fun grantThenRevoke() {
        val store = InMemoryKeyValueStore()
        val consent = DirectAccessConsent(store)
        val now = Instant.ofEpochSecond(1_700_000_000)
        consent.grant(DirectProvider.CODEX, now)
        assertTrue(consent.isGranted(DirectProvider.CODEX))
        assertEquals(now, consent.consentedAt(DirectProvider.CODEX))
        assertEquals(1_700_000_000.0, store.getDouble("directAccess.codex.consentedAt")!!, 0.0)
        assertEquals(1, store.getInt("directAccess.codex.noticeVersion"))
        val reloaded = DirectAccessConsent(store)
        assertTrue(reloaded.isGranted(DirectProvider.CODEX))
        reloaded.revoke(DirectProvider.CODEX)
        assertFalse(consent.isGranted(DirectProvider.CODEX))
        assertNull(store.getInt("directAccess.codex.noticeVersion"))
    }

    @Test fun olderNoticeVersionIsNotConsent() {
        val store = InMemoryKeyValueStore()
        store.putInt("directAccess.claude.noticeVersion", 0)
        store.putDouble("directAccess.claude.consentedAt", 1_700_000_000.0)
        assertFalse(DirectAccessConsent(store).isGranted(DirectProvider.CLAUDE))
    }

    @Test fun providersAreIndependent() {
        val consent = DirectAccessConsent(InMemoryKeyValueStore())
        consent.grant(DirectProvider.CLAUDE)
        assertTrue(consent.isGranted(DirectProvider.CLAUDE))
        assertFalse(consent.isGranted(DirectProvider.CODEX))
        consent.grant(DirectProvider.CODEX)
        consent.revoke(DirectProvider.CLAUDE)
        assertFalse(consent.isGranted(DirectProvider.CLAUDE))
        assertNotNull(consent.consentedAt(DirectProvider.CODEX))
    }
}
