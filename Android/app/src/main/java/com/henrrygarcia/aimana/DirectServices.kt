package com.henrrygarcia.aimana

import com.henrrygarcia.aimana.core.DirectAccessConsent
import com.henrrygarcia.aimana.core.DirectAndRelay
import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.core.ProviderState
import com.henrrygarcia.aimana.core.RelayEntry
import com.henrrygarcia.aimana.core.RelayEnvelope
import com.henrrygarcia.aimana.core.auth.PhoneClaudeTokens
import com.henrrygarcia.aimana.core.auth.PhoneCodexTokens
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.providers.BalanceClient
import com.henrrygarcia.aimana.core.providers.BalanceDescriptor
import com.henrrygarcia.aimana.core.providers.ClaudeUsageClient
import com.henrrygarcia.aimana.core.providers.CodexUsageClient
import com.henrrygarcia.aimana.core.providers.CopilotAllowance
import com.henrrygarcia.aimana.core.providers.CopilotClient
import com.henrrygarcia.aimana.core.providers.CopilotPlan
import com.henrrygarcia.aimana.core.providers.CredentialKey
import com.henrrygarcia.aimana.core.providers.FixedKey
import com.henrrygarcia.aimana.core.providers.OpenRouterClient
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.CredentialStore
import com.henrrygarcia.aimana.core.storage.KeyValueStore
import java.time.Instant

/// What the dashboard shows: the relay file, with Claude and Codex replaced by this phone's own direct reading
/// while the user's consent holds. `notes`: providers showing relay data because direct access failed (error code).
data class MergedUsage(val envelope: RelayEnvelope?, val notes: Map<String, String> = emptyMap())

/// This phone's sign-ins and the direct-access rule, in one place (no Android APIs, so it is unit-tested on the JVM).
/// A provider read with the user's own API key, through its official API (no consent notice needed).
data class ApiProvider(val id: String, val name: String, val credentialKey: String)

class DirectServices(
    private val credentials: CredentialStore,
    private val preferences: KeyValueStore,
    private val transport: HttpTransport,
    private val clock: () -> Instant = Instant::now,
) {
    val consent = DirectAccessConsent(preferences)
    val claudeTokens = PhoneClaudeTokens(credentials, transport, clock)
    val codexTokens = PhoneCodexTokens(credentials, transport, clock)
    private val claude = ClaudeUsageClient(transport, claudeTokens, clock, BackoffGate.shared("claude", preferences),
                                           isAllowed = { isActive(DirectProvider.CLAUDE) })
    private val codex = CodexUsageClient(transport, codexTokens, clock, BackoffGate.shared("codex", preferences),
                                         isAllowed = { isActive(DirectProvider.CODEX) })

    /// In the order "More providers" lists them.
    val apiProviders = BalanceDescriptor.all.map { ApiProvider(it.id, it.name, it.credentialKey) } +
        listOf(ApiProvider(OpenRouterClient.PROVIDER_ID, OpenRouterClient.NAME, CredentialKey.OPENROUTER),
               ApiProvider(CopilotClient.PROVIDER_ID, CopilotClient.NAME, CredentialKey.COPILOT))

    /// Stored as the plan's position in `CopilotPlan.entries` (the store keeps numbers only).
    var copilotAllowance: CopilotAllowance
        get() = CopilotAllowance(preferences.getInt(CopilotPlan.PLAN_KEY)?.let { CopilotPlan.entries.getOrNull(it) } ?: CopilotPlan.PRO,
                                 preferences.getDouble(CopilotPlan.CUSTOM_USD_KEY))
        set(value) {
            preferences.putInt(CopilotPlan.PLAN_KEY, value.plan.ordinal)
            value.customUSD?.takeIf { it.isFinite() && it > 0 }?.let { preferences.putDouble(CopilotPlan.CUSTOM_USD_KEY, it) }
                ?: preferences.remove(CopilotPlan.CUSTOM_USD_KEY)
        }

    private fun storedKey(credentialKey: String) = AccessTokenSource { FixedKey(credentials.read(credentialKey).orEmpty()).credentials() }

    /// One client per provider for the app's lifetime, so region hosts, teams and logins stay remembered.
    private val apiClients: Map<String, suspend () -> UsageInfo> = BalanceDescriptor.all.associate { d ->
        d.id to BalanceClient(d, transport, storedKey(d.credentialKey), clock, BackoffGate.shared(d.id, preferences))::fetch
    } + mapOf(
        OpenRouterClient.PROVIDER_ID to OpenRouterClient(transport, storedKey(CredentialKey.OPENROUTER), clock,
                                                         BackoffGate.shared(OpenRouterClient.PROVIDER_ID, preferences))::fetch,
        CopilotClient.PROVIDER_ID to CopilotClient(transport, storedKey(CredentialKey.COPILOT), { copilotAllowance }, clock,
                                                   BackoffGate.shared(CopilotClient.PROVIDER_ID, preferences))::fetch,
    )

    private fun provider(id: String) = apiProviders.first { it.id == id }

    fun hasKey(id: String) = !credentials.read(provider(id).credentialKey).isNullOrBlank()

    /// Checks the key with one reading and saves it (trimmed) only if the provider accepts it. Throws the `UsageError`.
    suspend fun saveKey(id: String, key: String) {
        val trimmed = key.trim()
        when (id) {
            OpenRouterClient.PROVIDER_ID -> OpenRouterClient.validate(trimmed, transport)
            CopilotClient.PROVIDER_ID -> CopilotClient.validate(trimmed, copilotAllowance, transport)
            else -> BalanceClient.validate(BalanceDescriptor.descriptor(id)!!, trimmed, transport)
        }
        credentials.write(trimmed, provider(id).credentialKey)
    }

    fun removeKey(id: String) = credentials.delete(provider(id).credentialKey)

    /// Consent given and a session stored on this phone.
    fun isActive(provider: DirectProvider): Boolean = consent.isGranted(provider) && when (provider) {
        DirectProvider.CLAUDE -> claudeTokens.isSignedIn
        DirectProvider.CODEX -> codexTokens.isSignedIn
    }

    /// Signing out deletes this phone's session and withdraws the consent: the next sign-in shows the notice again.
    suspend fun signOut(provider: DirectProvider) {
        when (provider) {
            DirectProvider.CLAUDE -> claudeTokens.signOut()
            DirectProvider.CODEX -> codexTokens.signOut()
        }
        consent.revoke(provider)
    }

    suspend fun merge(relay: RelayEnvelope?): MergedUsage {
        fun relayOnly(id: String): ProviderState = relay?.provider(id)?.first.let { ProviderState(id, it, if (it == null) UsageError.RelayUnavailable else null) }
        // Each reading is checked again once all are in: a sign-out, a withdrawn consent or a removed key while later
        // providers were still loading must not bring an earlier direct reading back.
        val states = listOf(DirectProvider.CLAUDE to claude::fetch, DirectProvider.CODEX to codex::fetch).map { (provider, fetch) ->
            provider to DirectAndRelay(fetch, { relay?.provider(provider.id)?.first }, { isActive(provider) }).state(provider.id)
        }.map { (provider, state) -> if (isActive(provider)) state else relayOnly(provider.id) }
        // API balances only for keys saved on this phone; other relay entries pass through.
        val apiStates = apiProviders.filter { hasKey(it.id) }.map { api ->
            DirectAndRelay(apiClients.getValue(api.id), { relay?.provider(api.id)?.first }, { hasKey(api.id) }).state(api.id)
        }.map { if (hasKey(it.providerID)) it else relayOnly(it.providerID) }
        if (relay == null && (states + apiStates).none { it.usage != null || it.error != null && it.error != UsageError.RelayUnavailable }) {
            return MergedUsage(null)
        }
        val direct = (states + apiStates).associateBy { it.providerID }
        val entries = (relay?.entries.orEmpty().filter { it.providerID !in direct } + states.map { state ->
            RelayEntry(state.providerID, state.usage, if (state.usage == null) state.error?.let(::code) else null,
                       if (state.usage != null && !state.isFallback && relay?.provider(state.providerID)?.first != state.usage) "endpoint"
                       else relay?.entries?.firstOrNull { it.providerID == state.providerID }?.source)
        } + apiStates.map { state ->
            RelayEntry(state.providerID, state.usage, if (state.usage == null) state.error?.let(::code) else null,
                       if (state.isFallback) relay?.entries?.firstOrNull { it.providerID == state.providerID }?.source else "api")
        }).filter { it.usage != null || it.error != null && !(relay == null && it.error == "relayUnavailable") }
        val envelope = RelayEnvelope(1, relay?.generatedAt ?: clock(), entries, relay?.costs.orEmpty(), relay?.history.orEmpty())
        val notes = (states + apiStates).filter { it.isFallback && it.error != null }.associate { it.providerID to code(it.error!!) }
        return MergedUsage(envelope, notes)
    }

    private fun code(error: UsageError): String = when (error) {
        UsageError.Unauthenticated, UsageError.UnsupportedCredentialStore -> "unauthenticated"
        is UsageError.RateLimited -> "rateLimited"
        UsageError.Decoding -> "decoding"
        UsageError.Network -> "network"
        is UsageError.Server -> "server"
        UsageError.RelayUnavailable -> "relayUnavailable"
    }
}
