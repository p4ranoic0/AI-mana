package com.henrrygarcia.aimana

import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.core.RelayCodec
import com.henrrygarcia.aimana.core.auth.ClaudeSession
import com.henrrygarcia.aimana.core.auth.ClaudeSessionCodec
import com.henrrygarcia.aimana.core.auth.PhoneClaudeTokens
import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.storage.InMemoryCredentialStore
import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class Recording(private val body: String) : HttpTransport {
    val requests = mutableListOf<HttpRequest>()
    override suspend fun send(request: HttpRequest): HttpResponse { requests += request; return HttpResponse(200, emptyMap(), body) }
}

class DirectServicesTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val usageBody = """{"five_hour":{"utilization":10.0,"resets_at":"2099-01-01T00:00:00Z"}}"""
    private val relay = RelayCodec.decode("""{"version":1,"generatedAt":"2027-01-10T00:00:00Z","entries":[
        {"providerID":"claude","source":"statusline","usage":{"providerID":"claude","providerName":"Claude Code","windows":[{"kind":"session","usedPercent":42,"windowMinutes":300}],"lastUpdated":"2027-01-10T00:00:00Z"}}],
        "costs":[{"providerID":"claude","generatedAt":"2027-01-10T00:00:00Z","days":[{"day":"2027-01-10","usd":3.5}]}]}""")
    private val credentials = InMemoryCredentialStore().apply {
        // A session saved earlier (for example by a previous build), still valid.
        write(ClaudeSessionCodec.encode(ClaudeSession("A", "R", now.plusSeconds(3600))), PhoneClaudeTokens.STORE_KEY)
    }
    private fun services(transport: Recording) = DirectServices(credentials, InMemoryKeyValueStore(), transport, clock = { now })

    @Test fun inheritedSessionWithoutConsentStaysRelay() = runBlocking {
        val transport = Recording(usageBody)
        val merged = services(transport).merge(relay)
        assertEquals(42.0, merged.envelope!!.provider("claude").first!!.primary!!.usedPercent, 0.0)
        assertTrue(transport.requests.isEmpty())
    }

    @Test fun consentedSessionUsesDirectWithRelayCosts() = runBlocking {
        val transport = Recording(usageBody)
        val services = services(transport)
        services.consent.grant(DirectProvider.CLAUDE)
        val claude = services.merge(relay).envelope!!.provider("claude").first!!
        assertEquals(10.0, claude.primary!!.usedPercent, 0.0)
        assertEquals(3.5, claude.cost!!.days.single().usd, 0.0)
        assertEquals(1, transport.requests.size)
    }

    @Test fun signOutRevokesConsentAndShowsRelay() = runBlocking {
        val services = services(Recording(usageBody))
        services.consent.grant(DirectProvider.CLAUDE)
        services.signOut(DirectProvider.CLAUDE)
        assertFalse(services.consent.isGranted(DirectProvider.CLAUDE))
        assertFalse(services.claudeTokens.isSignedIn)
        assertEquals(42.0, services.merge(relay).envelope!!.provider("claude").first!!.primary!!.usedPercent, 0.0)
    }

    @Test fun noRelayShowsDirectQuotasWithoutCosts() = runBlocking {
        val services = services(Recording(usageBody))
        services.consent.grant(DirectProvider.CLAUDE)
        val merged = services.merge(null)
        val claude = merged.envelope!!.provider("claude").first!!
        assertEquals(10.0, claude.primary!!.usedPercent, 0.0)
        assertNull(claude.cost)
        assertTrue(merged.envelope!!.costs.isEmpty())
    }

    @Test fun nothingAtAllIsNoEnvelope() = runBlocking {
        assertNull(services(Recording(usageBody)).merge(null).envelope)
    }

    private class Scripted(private val replies: MutableList<HttpResponse>) : HttpTransport {
        val requests = mutableListOf<HttpRequest>()
        override suspend fun send(request: HttpRequest): HttpResponse { requests += request; return replies.removeAt(0) }
    }
    private val deepSeekBody = """{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"7.50"}]}"""

    @Test fun savedApiKeyReadsItsBalanceWithoutConsent() = runBlocking {
        val transport = Scripted(MutableList(3) { HttpResponse(200, emptyMap(), deepSeekBody) })
        val services = DirectServices(InMemoryCredentialStore(), InMemoryKeyValueStore(), transport, clock = { now })
        services.saveKey("deepseek", "  sk-1 ")
        assertTrue(services.hasKey("deepseek"))
        val deepSeek = services.merge(null).envelope!!.provider("deepseek").first!!
        assertEquals(7.5, deepSeek.details.single().remaining, 0.0)
        assertEquals("Bearer sk-1", transport.requests.last().headers["Authorization"])
        // No relay file and no direct sign-in: Claude and Codex are simply absent, not "relay missing".
        assertEquals(listOf("deepseek"), services.merge(null).envelope!!.entries.map { it.providerID })
    }

    @Test fun rejectedApiKeyIsNotSaved() = runBlocking {
        val store = InMemoryCredentialStore()
        val services = DirectServices(store, InMemoryKeyValueStore(), Scripted(mutableListOf(HttpResponse(401, emptyMap(), ""))), clock = { now })
        val error = runCatching { services.saveKey("openrouter", "bad") }.exceptionOrNull()
        assertEquals(com.henrrygarcia.aimana.core.providers.UsageError.Unauthenticated, error)
        assertNull(store.read(com.henrrygarcia.aimana.core.providers.CredentialKey.OPENROUTER))
    }

    @Test fun removedApiKeyLeavesTheRelayReading() = runBlocking {
        val relayWithBalance = RelayCodec.decode("""{"version":1,"generatedAt":"2027-01-10T00:00:00Z","entries":[
            {"providerID":"deepseek","usage":{"providerID":"deepseek","providerName":"DeepSeek","windows":[],"lastUpdated":"2027-01-10T00:00:00Z",
             "details":[{"kind":"creditBalance","remaining":1,"currency":"USD"}]}}]}""")
        val transport = Scripted(mutableListOf(HttpResponse(200, emptyMap(), deepSeekBody)))
        val services = DirectServices(InMemoryCredentialStore(), InMemoryKeyValueStore(), transport, clock = { now })
        services.saveKey("deepseek", "sk-1")
        services.removeKey("deepseek")
        assertFalse(services.hasKey("deepseek"))
        assertEquals(1.0, services.merge(relayWithBalance).envelope!!.provider("deepseek").first!!.details.single().remaining, 0.0)
        assertEquals(1, transport.requests.size)   // only the check when saving
    }

    @Test fun copilotAllowanceIsRemembered() {
        val preferences = InMemoryKeyValueStore()
        DirectServices(InMemoryCredentialStore(), preferences, Recording(""), clock = { now })
            .copilotAllowance = com.henrrygarcia.aimana.core.providers.CopilotAllowance(com.henrrygarcia.aimana.core.providers.CopilotPlan.CUSTOM, 12.0)
        val again = DirectServices(InMemoryCredentialStore(), preferences, Recording(""), clock = { now }).copilotAllowance
        assertEquals(com.henrrygarcia.aimana.core.providers.CopilotPlan.CUSTOM, again.plan)
        assertEquals(12.0, again.customUSD!!, 0.0)
    }

    @Test fun signOutDuringARefreshDoesNotBringTheReadingBack() = runBlocking {
        val codexBody = """{"rate_limit":{"primary_window":{"used_percent":5,"reset_at":4102444800,"limit_window_seconds":18000}}}"""
        lateinit var services: DirectServices
        val transport = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResponse {
                // Claude was already read; the user signs out of Claude while Codex is still loading.
                if ("chatgpt.com" in request.url) { services.signOut(DirectProvider.CLAUDE); return HttpResponse(200, emptyMap(), codexBody) }
                return HttpResponse(200, emptyMap(), usageBody)
            }
        }
        credentials.write(com.henrrygarcia.aimana.core.auth.CodexSessionCodec.encode(
            com.henrrygarcia.aimana.core.auth.CodexSession("CA", "CR", "acct", "pro", now.plusSeconds(3600))),
            com.henrrygarcia.aimana.core.auth.PhoneCodexTokens.STORE_KEY)
        services = DirectServices(credentials, InMemoryKeyValueStore(), transport, clock = { now })
        services.consent.grant(DirectProvider.CLAUDE)
        services.consent.grant(DirectProvider.CODEX)
        val merged = services.merge(relay).envelope!!
        assertEquals(42.0, merged.provider("claude").first!!.primary!!.usedPercent, 0.0)   // the relay's, not the direct 10 %
        assertEquals(5.0, merged.provider("codex").first!!.primary!!.usedPercent, 0.0)
    }
}
