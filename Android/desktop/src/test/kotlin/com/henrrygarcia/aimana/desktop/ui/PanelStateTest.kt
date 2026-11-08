package com.henrrygarcia.aimana.desktop.ui

import com.henrrygarcia.aimana.core.ProviderState
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.providers.UsageError
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PanelStateTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val strings = Strings(Locale.ENGLISH)
    private fun usage(vararg windows: UsageWindow) = UsageInfo("claude", "Claude Code", windows.toList(), null, now)

    @Test fun headlineIsTheFullestCurrentLane() {
        val row = panelRows(listOf(ProviderState("claude", usage(UsageWindow("session", 18.0, 300, now.plusSeconds(600)),
                                                                   UsageWindow("weekly", 61.0, 10080, now.plusSeconds(6000))), null)), strings, now).single()
        assertEquals("61%", row.headline)
        assertEquals(2, row.lanes.size)
    }

    @Test fun panelStateShowsFallbackLabel() {
        val row = panelRows(listOf(ProviderState("claude", usage(UsageWindow("session", 42.0, 300)), UsageError.Unauthenticated,
                                                 isFallback = true)), strings, now).single()
        assertEquals("42%", row.headline)
        assertEquals("Showing relay data — direct access: Sign in to Claude Code on this computer.", row.message)
    }

    @Test fun oldRelayReadingSaysWhy() {
        val silent = UsageInfo("claude", "Claude Code", listOf(UsageWindow("session", 30.0)), null, now.minusSeconds(3 * 3600),
                               source = "endpoint", relayPublishedAt = now.minusSeconds(3 * 3600))
        assertEquals("Your computer hasn't published for 3h. Check that it's on and AI·mana is running there.",
                     panelRows(listOf(ProviderState("claude", silent, null)), strings, now).single().message)
        val idle = silent.copy(source = "logs", relayPublishedAt = now.minusSeconds(60))
        assertEquals("No recent use on this computer: this updates the next time you use it.",
                     panelRows(listOf(ProviderState("claude", idle, null)), strings, now).single().message)
    }

    @Test fun panelStateNeverShowsZeroForMissingData() {
        val row = panelRows(listOf(ProviderState("codex", null, UsageError.RelayUnavailable)), strings, now).single()
        assertNull(row.headline)
        assertTrue(row.lanes.isEmpty())
        assertEquals("No local data yet.", row.message)
    }

    @Test fun keyringIsNotASignOut() {
        val row = panelRows(listOf(ProviderState("codex", null, UsageError.UnsupportedCredentialStore)), strings, now).single()
        assertTrue(row.message!!.contains("keyring"))
    }

    @Test fun extraUsageOnlyIsNotNoData() {
        val usage = UsageInfo("claude", "Claude Code", emptyList(), null, now,
                              details = listOf(com.henrrygarcia.aimana.core.UsageDetail("extraUsage", 74.5, 100.0, "USD", 25.5)))
        val row = panelRows(listOf(ProviderState("claude", usage, null)), strings, now).single()
        assertNull(row.message)
        assertEquals(listOf("Extra usage: $25.50 of $100.00"), row.details)
    }

    @Test fun costAndCreditsAreShown() {
        val today = java.time.LocalDate.now(java.time.ZoneOffset.UTC).toString()
        val cost = com.henrrygarcia.aimana.core.CostReport("codex", now, listOf(com.henrrygarcia.aimana.core.DailyCost(today, usd = 12.345)))
        val usage = UsageInfo("codex", "OpenAI Codex", listOf(UsageWindow("session", 5.0, 300)), null, now, cost = cost,
                              details = listOf(com.henrrygarcia.aimana.core.UsageDetail("creditBalance", 12.5, currency = "USD"),
                                               com.henrrygarcia.aimana.core.UsageDetail("resetCredits", 2.0)))
        val row = panelRows(listOf(ProviderState("codex", usage, null)), strings, now, java.time.ZoneOffset.UTC).single()
        assertEquals(listOf("Credit balance: $12.50", "Rate-limit resets available: 2"), row.details)
        assertEquals("Last 7 days ≈ $12.35 at API prices", row.cost)
    }

    @Test fun eachRowSaysHowOldItsDataIs() {
        // An old relay file read just now must not look fresh.
        val old = UsageInfo("claude", "Claude Code", listOf(UsageWindow("session", 42.0, 300)), null, Instant.parse("2027-01-09T15:30:00Z"))
        val row = panelRows(listOf(ProviderState("claude", old, null)), strings, now, java.time.ZoneOffset.UTC).single()
        assertEquals("As of Jan 9, 15:30", row.asOf)
        val fresh = UsageInfo("claude", "Claude Code", listOf(UsageWindow("session", 42.0, 300)), null, now)
        assertEquals("As of 00:00", panelRows(listOf(ProviderState("claude", fresh, null)), strings, now, java.time.ZoneOffset.UTC).single().asOf)
    }

    @Test fun everyLanguageHasEveryKey() {
        val english = Strings.keys(Locale.ENGLISH)
        for (tag in listOf("es", "pt-BR", "fr", "de", "it")) assertEquals(tag, english, Strings.keys(Locale.forLanguageTag(tag)))
    }

    @Test fun noticeTextMatchesApprovedCopy() {
        // The Mac notice the owner approved, with the Keychain/~/.claude wording adapted to a computer without Keychain.
        val catalog = Json.parseToJsonElement(Files.readString(Path.of("../../AImana/Mac/Localizable.xcstrings"))).jsonObject["strings"]!!.jsonObject
        val mac = catalog.keys.single { it.startsWith("Off by default. When on, AI·mana reads the session that Claude Code keeps") }
        assertEquals(mac.replace("in your Keychain or ~/.claude on this Mac", "in its .claude folder on this computer")
                        .replace("AI·mana uses the local data", "AI·mana uses the local data"), strings["notice.claude"])
        val macCodex = catalog.keys.single { it.startsWith("Off by default. When on, AI·mana reads the session that Codex keeps") }
        assertEquals(macCodex.replace("~/.codex/auth.json on this Mac", "its .codex folder on this computer"), strings["notice.codex"])
        assertTrue(catalog[mac]!!.jsonObject["localizations"]!!.jsonObject["en"]!!.jsonObject["stringUnit"]!!.jsonObject["value"]!!.jsonPrimitive.content.isNotEmpty())
    }
}
