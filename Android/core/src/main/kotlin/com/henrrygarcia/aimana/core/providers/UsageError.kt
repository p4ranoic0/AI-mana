package com.henrrygarcia.aimana.core.providers

import java.time.Instant
import java.time.OffsetDateTime

/// Same cases as the Swift `UsageProviderError`.
sealed class UsageError : Exception() {
    /// Missing, expired or revoked credentials. Requires user action.
    data object Unauthenticated : UsageError() { private fun readResolve(): Any = Unauthenticated }
    data class RateLimited(val until: Instant?) : UsageError()
    data object Decoding : UsageError() { private fun readResolve(): Any = Decoding }
    data object Network : UsageError() { private fun readResolve(): Any = Network }
    data class Server(val status: Int) : UsageError()
    data object RelayUnavailable : UsageError() { private fun readResolve(): Any = RelayUnavailable }
    /// The CLI keeps its sign-in somewhere AI·mana can't read (the system keyring). Not a sign-out.
    data object UnsupportedCredentialStore : UsageError() { private fun readResolve(): Any = UnsupportedCredentialStore }

    /// Errors after which the last known data is still meaningful.
    val keepsStaleData: Boolean get() = this !is Unauthenticated && this !is UnsupportedCredentialStore
}

data class AccessCredential(val token: String, val accountID: String? = null, val plan: String? = null) {
    override fun toString() = "AccessCredential(token=<redacted>, accountID=${accountID != null}, plan=$plan)"
}

fun interface AccessTokenSource {
    suspend fun credentials(): AccessCredential
}

internal object IsoDate {
    fun parse(value: String?): Instant? {
        if (value.isNullOrEmpty()) return null
        return runCatching { Instant.parse(value) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
    }
}
