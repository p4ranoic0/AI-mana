package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.CredentialStore
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/// A phone sign-in whose refresh token rotates: redeeming one that was already used ends the session.
interface RotatingSession {
    val refreshToken: String
    val expiresAt: Instant
}

interface SessionCodec<S> {
    fun encode(session: S): String
    fun decode(text: String): S?
}

/// Keeps one rotating session in a `CredentialStore` and renews it shortly before it expires. Same rules as the Swift
/// `SessionKeeper`: one renewal for all callers, the rotated token saved before it is used, and a sign-in or sign-out
/// that happens meanwhile always wins (renewal, sign-in and sign-out share one lock).
class SessionKeeper<S : RotatingSession>(
    private val key: String,
    private val store: CredentialStore,
    private val clock: () -> Instant,
    private val renewSkew: Duration,
    private val codec: SessionCodec<S>,
    private val renew: suspend (S, Instant) -> S,
) {
    private val mutex = Mutex()
    /// Renewal attempts so far, and how the last one failed (for the refresh token it tried): callers that were
    /// waiting during that attempt get the same failure instead of asking the server again.
    @Volatile private var attempts = 0L
    private var lastFailure: Pair<String, Throwable>? = null
    @Volatile private var renewing = false

    fun load(): S? = runCatching { store.read(key) }.getOrNull()?.let(codec::decode)

    suspend fun save(session: S) = mutex.withLock { write(session) }

    suspend fun delete() = mutex.withLock { store.delete(key) }

    private fun write(session: S) = store.write(codec.encode(session), key)

    private fun isFresh(session: S) = Duration.between(clock(), session.expiresAt) > renewSkew

    /// A session valid for at least `renewSkew`, renewing it if needed.
    suspend fun current(): S {
        val session = load() ?: throw UsageError.Unauthenticated
        if (isFresh(session)) return session
        // Arriving while an attempt runs counts as waiting for that attempt.
        val seen = attempts - (if (renewing) 1 else 0)
        return mutex.withLock {
            // Another caller may have renewed while this one waited for the lock.
            val stored = load() ?: throw UsageError.Unauthenticated
            if (isFresh(stored)) return@withLock stored
            // …or failed to: share that outcome.
            lastFailure?.takeIf { attempts > seen && it.first == stored.refreshToken }?.let { throw it.second }
            attempts++
            lastFailure = null
            renewing = true
            // Not cancellable: once the server has rotated the refresh token, the new one must be saved.
            withContext(NonCancellable) {
                try {
                    try {
                        renewAndPersist(stored)
                    } catch (e: UsageError.Unauthenticated) {
                        // `invalid_grant`: look once more before declaring the sign-in lost; another writer may have rotated it.
                        val latest = load()
                        if (latest == null || latest.refreshToken == stored.refreshToken) throw e
                        if (isFresh(latest)) latest else renewAndPersist(latest)
                    }
                } catch (e: Exception) {
                    lastFailure = stored.refreshToken to e
                    throw e
                } finally {
                    renewing = false
                }
            }
        }
    }

    private suspend fun renewAndPersist(session: S): S {
        val renewed = renew(session, clock())
        // Signed out meanwhile: do not bring the session back.
        val current = load() ?: throw UsageError.Unauthenticated
        // Signed in again (or renewed elsewhere) meanwhile: that newer session wins.
        if (current.refreshToken != session.refreshToken) return current
        write(renewed)   // persist the rotated refresh token first
        return renewed
    }
}

object ClaudeSessionCodec : SessionCodec<ClaudeSession> {
    override fun encode(session: ClaudeSession) = kotlinx.serialization.json.buildJsonObject {
        put("accessToken", kotlinx.serialization.json.JsonPrimitive(session.accessToken))
        put("refreshToken", kotlinx.serialization.json.JsonPrimitive(session.refreshToken))
        put("expiresAt", kotlinx.serialization.json.JsonPrimitive(session.expiresAt.toString()))
    }.toString()

    override fun decode(text: String): ClaudeSession? = runCatching {
        val o = kotlinx.serialization.json.Json.parseToJsonElement(text) as kotlinx.serialization.json.JsonObject
        fun s(k: String) = (o[k] as kotlinx.serialization.json.JsonPrimitive).content
        ClaudeSession(s("accessToken"), s("refreshToken"), Instant.parse(s("expiresAt")))
    }.getOrNull()
}
