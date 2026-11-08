package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.providers.AccessCredential
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.storage.CredentialStore
import java.time.Duration
import java.time.Instant

/// This device's own Claude access token, renewed shortly before it expires (Swift: `PhoneClaudeTokens`).
class PhoneClaudeTokens(store: CredentialStore, private val transport: HttpTransport, clock: () -> Instant = Instant::now) : AccessTokenSource {
    private val keeper = SessionKeeper(STORE_KEY, store, clock, RENEW_SKEW, ClaudeSessionCodec) { session, now ->
        ClaudeOAuth.refresh(session, transport, now)
    }

    val isSignedIn: Boolean get() = keeper.load() != null

    suspend fun save(session: ClaudeSession) = keeper.save(session)

    suspend fun signOut() = keeper.delete()

    override suspend fun credentials() = AccessCredential(keeper.current().accessToken)

    companion object {
        const val STORE_KEY = "claude.phone.session"
        val RENEW_SKEW: Duration = Duration.ofSeconds(120)
    }
}
