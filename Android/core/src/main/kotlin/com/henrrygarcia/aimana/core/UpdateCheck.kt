package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.storage.KeyValueStore
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/// A published release newer than the running app. The page is built from the version, never taken from the response.
data class AppUpdate(val version: String) {
    val pageUrl get() = "https://github.com/p4ranoic0/AI-mana/releases/tag/v$version"
}

/// Asks GitHub for the latest public release at most once a day, so an install that fell behind says so instead of
/// failing silently. Anonymous request, no identifiers; failures are silent and keep the last answer. Can be turned off.
class UpdateCheck(
    private val transport: HttpTransport,
    private val currentVersion: String,
    private val store: KeyValueStore,
    private val clock: () -> Instant = Instant::now,
) {
    var enabled: Boolean
        get() = store.getInt(OFF_KEY) != 1
        set(value) = if (value) store.remove(OFF_KEY) else store.putInt(OFF_KEY, 1)

    /// The remembered answer, without asking the network.
    fun available(): AppUpdate? {
        if (!enabled) return null
        val latest = store.getInt(LATEST_KEY) ?: return null
        val current = versionCode(currentVersion) ?: return null
        return if (latest > current) AppUpdate(versionName(latest)) else null
    }

    suspend fun refresh(): AppUpdate? {
        if (!enabled) return null
        val now = clock()
        val last = store.getDouble(CHECKED_KEY)?.let { Instant.ofEpochSecond(it.toLong()) }
        if (last != null && last.isAfter(now.minus(INTERVAL)) && !last.isAfter(now)) return available()
        val latest = try {
            val response = transport.send(HttpRequest(LATEST_URL, mapOf("Accept" to "application/vnd.github+json")))
            if (response.status == 200) Json.parseToJsonElement(response.body).jsonObject["tag_name"]?.jsonPrimitive?.contentOrNull
                ?.let(::versionCode) else null
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
        if (latest != null) {
            store.putInt(LATEST_KEY, latest)
            store.putDouble(CHECKED_KEY, now.epochSecond.toDouble())
        } else {
            // Try again in an hour rather than tomorrow.
            store.putDouble(CHECKED_KEY, now.minus(INTERVAL).plus(RETRY).epochSecond.toDouble())
        }
        return available()
    }

    companion object {
        const val LATEST_URL = "https://api.github.com/repos/p4ranoic0/AI-mana/releases/latest"
        val INTERVAL: Duration = Duration.ofHours(24)
        private val RETRY: Duration = Duration.ofHours(1)
        private const val OFF_KEY = "updates.off"
        private const val LATEST_KEY = "updates.latest"
        private const val CHECKED_KEY = "updates.checkedAt"

        /// "v1.2.3" → 10203, like Android's versionCode. Pre-releases and parts over 99 are not comparable: null.
        fun versionCode(version: String): Int? {
            val parts = version.removePrefix("v").split('.')
            if (parts.size != 3) return null
            val numbers = parts.map { part -> part.toIntOrNull()?.takeIf { it in 0..99 && part.all(Char::isDigit) } ?: return null }
            return numbers[0] * 10_000 + numbers[1] * 100 + numbers[2]
        }

        private fun versionName(code: Int) = "${code / 10_000}.${code / 100 % 100}.${code % 100}"
    }
}
