package com.henrrygarcia.aimana.core.net

import com.henrrygarcia.aimana.core.storage.KeyValueStore
import java.time.Instant

/// Remembers a 429 so repeat calls inside the window never reach the network. With a key and a store the block is
/// shared by every instance for the same provider (each refresh builds new clients); the latest block always wins.
class BackoffGate(private val key: String? = null, private val store: KeyValueStore? = null) {
    private var blockedUntil: Instant? = null

    @Synchronized fun check(now: Instant): Instant? {
        val until = listOfNotNull(blockedUntil, persisted()).maxOrNull() ?: return null
        return until.takeIf { it.isAfter(now) }
    }

    @Synchronized fun block(until: Instant) {
        val latest = listOfNotNull(blockedUntil, persisted(), until).max()
        blockedUntil = latest
        if (key != null && store != null) store.putDouble(key, latest.epochSecond + latest.nano / 1e9)
    }

    private fun persisted(): Instant? {
        val seconds = key?.let { store?.getDouble(it) } ?: return null
        return Instant.ofEpochSecond(seconds.toLong(), ((seconds - seconds.toLong()) * 1e9).toLong())
    }

    companion object {
        /// The shared gate for one provider's direct endpoint (`backoff.<providerID>.until`, as on Apple platforms).
        fun shared(providerID: String, store: KeyValueStore) = BackoffGate("backoff.$providerID.until", store)
    }
}
