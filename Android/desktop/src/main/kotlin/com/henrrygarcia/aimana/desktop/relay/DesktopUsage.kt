package com.henrrygarcia.aimana.desktop.relay

import com.henrrygarcia.aimana.core.DirectAccessConsent
import com.henrrygarcia.aimana.core.DirectAndRelay
import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.core.ProviderState
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.providers.UsageError

/// What the tray shows: the relay worker's local data, plus each provider's direct reading while the user's consent
/// holds (checked before and after every request). Merged in memory only.
class DesktopUsage(
    private val worker: RelayWorker,
    private val consent: DirectAccessConsent,
    private val claude: suspend () -> UsageInfo,
    private val codex: suspend () -> UsageInfo,
    /// False in the panel process: only the tray runs usage-relay; the panel reads the file it published.
    private val publish: Boolean = true,
) {
    /// The relay worker's last problem, shown in the panel; direct access keeps working without it.
    val relayProblem: String? get() = worker.lastError

    suspend fun refresh(): List<ProviderState> {
        val envelope = if (publish) worker.publishOnce() else worker.readLast()
        val relay = { provider: DirectProvider -> envelope?.provider(provider.id)?.first }
        val states = listOf(DirectProvider.CLAUDE to claude, DirectProvider.CODEX to codex).map { (provider, direct) ->
            provider to DirectAndRelay(direct, { relay(provider) }, { consent.isGranted(provider) }).state(provider.id)
        }
        // A consent withdrawn while a later provider was still loading: drop that provider's direct reading now.
        return states.map { (provider, state) ->
            if (consent.isGranted(provider)) state
            else ProviderState(provider.id, relay(provider), if (relay(provider) == null) UsageError.RelayUnavailable else null)
        }
    }
}
