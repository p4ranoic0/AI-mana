package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.providers.UsageError
import kotlin.coroutines.cancellation.CancellationException

/// One provider's outcome: fresh data, data with an error, or just an error. `isFallback`: `usage` is the relay's
/// because direct access failed with `error` (fresh data, not stale).
data class ProviderState(val providerID: String, val usage: UsageInfo?, val error: UsageError?, val isFallback: Boolean = false)

/// Direct reading when the user turned it on, the relay otherwise and as the source of costs and history. Same rules as
/// the Swift `HybridProvider` + `UsageService`: a direct failure never hides behind relay data, and a reading that
/// arrives after direct access was turned off is discarded.
class DirectAndRelay(
    private val direct: suspend () -> UsageInfo,
    private val relay: () -> UsageInfo?,
    private val isDirectEnabled: () -> Boolean,
) {
    suspend fun state(providerID: String): ProviderState {
        val fromRelay = relay()
        if (!isDirectEnabled()) {
            return ProviderState(providerID, fromRelay, if (fromRelay == null) UsageError.RelayUnavailable else null)
        }
        val live = try {
            direct()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Turned off meanwhile: plain relay data, not a direct-access error.
            if (!isDirectEnabled()) {
                return ProviderState(providerID, fromRelay, if (fromRelay == null) UsageError.RelayUnavailable else null)
            }
            val error = e as? UsageError ?: UsageError.Network
            return if (fromRelay != null) ProviderState(providerID, fromRelay, error, isFallback = true)
                   else ProviderState(providerID, null, error)
        }
        // Turned off while the request was in flight: the direct reading must not come back.
        if (!isDirectEnabled()) {
            return ProviderState(providerID, fromRelay, if (fromRelay == null) UsageError.RelayUnavailable else null)
        }
        return ProviderState(providerID, live.copy(plan = live.plan ?: fromRelay?.plan, cost = fromRelay?.cost,
                                                   history = fromRelay?.history.orEmpty()), null)
    }
}
