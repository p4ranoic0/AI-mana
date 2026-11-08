package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.storage.KeyValueStore
import java.time.Instant

/// Providers whose usage AI·mana can read straight from the provider's own (undocumented) endpoint.
enum class DirectProvider(val id: String) { CLAUDE("claude"), CODEX("codex");
    companion object { fun of(id: String) = entries.firstOrNull { it.id == id } }
}

/// The user's explicit opt-in to direct access, per provider; the only gate. Same keys and rules as the Swift
/// `DirectAccessConsent`: a consent counts only for the notice version the user accepted.
class DirectAccessConsent(private val store: KeyValueStore) {
    fun isGranted(provider: DirectProvider): Boolean {
        val version = store.getInt(versionKey(provider)) ?: return false
        return version >= CURRENT_NOTICE_VERSION && consentedAt(provider) != null
    }

    fun grant(provider: DirectProvider, now: Instant = Instant.now()) {
        store.putDouble(dateKey(provider), now.epochSecond + now.nano / 1e9)
        store.putInt(versionKey(provider), CURRENT_NOTICE_VERSION)
    }

    fun revoke(provider: DirectProvider) {
        store.remove(dateKey(provider))
        store.remove(versionKey(provider))
    }

    fun consentedAt(provider: DirectProvider): Instant? {
        val seconds = store.getDouble(dateKey(provider)) ?: return null
        return Instant.ofEpochSecond(seconds.toLong(), ((seconds - seconds.toLong()) * 1e9).toLong())
    }

    companion object {
        const val CURRENT_NOTICE_VERSION = 1
        private fun dateKey(p: DirectProvider) = "directAccess.${p.id}.consentedAt"
        private fun versionKey(p: DirectProvider) = "directAccess.${p.id}.noticeVersion"
    }
}
