package com.henrrygarcia.aimana

object ProviderPresentation {
    fun errorText(error: String?): Int = when (error) {
        "unauthenticated" -> R.string.signin_again
        "relayUnavailable" -> R.string.relay_missing
        "rateLimited" -> R.string.rate_limited
        "decoding" -> R.string.decoding_error
        "network" -> R.string.network_error
        "server" -> R.string.server_error
        else -> R.string.no_reading
    }
    fun sourceText(id: String): Int = if (id == "claude") R.string.source_claude else R.string.source_codex
}
