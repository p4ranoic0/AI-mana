package com.henrrygarcia.aimana.core.providers

import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class OpenRouterClientTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")
    private val keyBody = parityFixture("balances/openrouter.json")["response"].toString()

    private fun expectError(block: suspend () -> Unit): UsageError = runBlocking {
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }
    }

    @Test fun mapsParityFixture() = runBlocking {
        val fixture = parityFixture("balances/openrouter.json")
        val transport = MockTransport(mutableListOf(reply(200, keyBody), reply(200, fixture["credits"].toString())))
        val usage = OpenRouterClient(transport, FixedKey("sk-or"), { now }).fetch()
        assertMatchesExpected(usage, fixture["expected"] as JsonObject)
        assertEquals(listOf("/api/v1/key", "/api/v1/credits"), transport.requests.map { java.net.URI(it.url).path })
    }

    @Test fun openRouterCreditsAreBestEffort() = runBlocking {
        // An ordinary key gets 403 on /credits: the reading still succeeds, and /credits is not asked again for that key.
        val transport = MockTransport(mutableListOf(reply(200, keyBody), reply(403), reply(200, keyBody)))
        val client = OpenRouterClient(transport, FixedKey("sk-or"), { now })
        assertEquals(listOf("monthlySpend"), client.fetch().details.map { it.kind })
        client.fetch()
        assertEquals(listOf("/api/v1/key", "/api/v1/credits", "/api/v1/key"), transport.requests.map { java.net.URI(it.url).path })
        // A server error on /credits is not a denial either.
        val flaky = MockTransport(mutableListOf(reply(200, keyBody), reply(500)))
        assertEquals(listOf("monthlySpend"), OpenRouterClient(flaky, FixedKey("sk-or"), { now }).fetch().details.map { it.kind })
    }

    @Test fun rejectedKeyIsUnauthenticated() {
        assertEquals(UsageError.Unauthenticated, expectError { OpenRouterClient(MockTransport(mutableListOf(reply(401))), FixedKey("k"), { now }).fetch() })
    }

    @Test fun freeModelLaneStandsInWhenNothingElse() {
        val body = """{"data":{"limit":null,"usage":3.2,"usage_monthly":2.9,"is_free_tier":false,
            "free_model_daily_requests":{"used":0,"limit":1000,"remaining":1000}}}"""
        val usage = OpenRouterClient.map(body, null, now)
        assertEquals(listOf("free-requests"), usage.windows.map { it.kind })
        assertEquals(2.9, usage.details.single().used!!, 1e-9)
    }

    @Test fun freeModelLaneHiddenForPaidKeysThatDoNotUseIt() {
        val body = """{"data":{"limit":20,"limit_remaining":15,"limit_reset":"daily","usage":9,"usage_daily":5,
            "usage_monthly":9,"is_free_tier":false,"free_model_daily_requests":{"used":0,"limit":1000,"remaining":1000}}}"""
        val spend = OpenRouterClient.map(body, null, now).windows.single()
        assertEquals("spend-limit", spend.kind)
        assertEquals(25.0, spend.usedPercent, 1e-9)
        assertEquals(1440, spend.windowMinutes)
    }

    @Test fun weeklyResetStartsOnMonday() {
        val body = """{"data":{"limit":10,"limit_remaining":5,"limit_reset":"weekly","is_free_tier":true}}"""
        val spend = OpenRouterClient.map(body, null, now).windows.single()   // 2027-01-15 is a Friday
        assertEquals(Instant.parse("2027-01-18T00:00:00Z"), spend.resetsAt)
        assertEquals(10080, spend.windowMinutes)
        assertEquals("Free", OpenRouterClient.map(body, null, now).plan)
    }
}
