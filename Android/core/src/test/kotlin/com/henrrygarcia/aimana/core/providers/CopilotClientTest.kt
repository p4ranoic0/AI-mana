package com.henrrygarcia.aimana.core.providers

import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class CopilotClientTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")
    private val user = """{"login":"octo cat","id":1}"""

    private fun expectError(block: suspend () -> Unit): UsageError = runBlocking {
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }
    }

    private fun client(transport: MockTransport, plan: CopilotPlan = CopilotPlan.PRO) =
        CopilotClient(transport, FixedKey("ghp"), { CopilotAllowance(plan) }, { now })

    @Test fun mapsParityFixture() = runBlocking {
        val fixture = parityFixture("balances/copilot.json")
        val plan = CopilotPlan.fromWire(fixture["allowancePlan"]!!.jsonPrimitive.content)!!
        val transport = MockTransport(mutableListOf(reply(200, user), reply(200, fixture["response"].toString())))
        val usage = client(transport, plan).fetch()
        val expected = fixture["expected"] as JsonObject
        assertMatchesExpected(usage, expected)
        assertEquals(expected["plan"]!!.jsonPrimitive.content, usage.plan)
        val report = transport.requests[1]
        assertEquals("/users/octo%20cat/settings/billing/ai_credit/usage?year=2027&month=1",
                     java.net.URI(report.url).let { "${it.rawPath}?${it.rawQuery}" })
        assertEquals("2026-03-10", report.headers["X-GitHub-Api-Version"])
        assertEquals("application/vnd.github+json", report.headers["Accept"])
    }

    @Test fun legacyReportOnlyOn404() = runBlocking {
        val legacy = """{"usageItems":[{"product":"Copilot","unitType":"requests","grossQuantity":150,"grossAmount":6,"netAmount":0},
            {"product":"Actions","unitType":"minutes","grossQuantity":999,"grossAmount":9,"netAmount":9}]}"""
        val transport = MockTransport(mutableListOf(reply(200, user), reply(404), reply(200, legacy)))
        val usage = client(transport).fetch()
        assertEquals(50.0, usage.windows.single().usedPercent, 1e-9)   // 150 of Pro's 300 requests
        assertEquals(6.0, usage.details.single().used!!, 1e-9)
        assertEquals(UsageError.Decoding, expectError { client(MockTransport(mutableListOf(reply(200, user), reply(404), reply(404)))).fetch() })
    }

    @Test fun rejectedKeyIsUnauthenticated() {
        assertEquals(UsageError.Unauthenticated, expectError { client(MockTransport(mutableListOf(reply(401)))).fetch() })
        // A 403 without rate-limit signals is a missing permission, not a rate limit.
        assertEquals(UsageError.Unauthenticated, expectError { client(MockTransport(mutableListOf(reply(200, user), reply(403)))).fetch() })
    }

    @Test fun rateLimit403UsesTheResetHeader() {
        val reset = now.plusSeconds(600)
        val transport = MockTransport(mutableListOf(reply(403, headers = mapOf("x-ratelimit-remaining" to "0", "x-ratelimit-reset" to "${reset.epochSecond}"))))
        assertEquals(UsageError.RateLimited(reset), expectError { client(transport).fetch() })
    }

    @Test fun customAmountAndNoAllowance() {
        val body = """{"usageItems":[{"grossAmount":5,"netAmount":0}]}"""
        assertEquals(50.0, CopilotClient.map(body, CopilotUnit.AI_CREDITS, CopilotAllowance(CopilotPlan.CUSTOM, 10.0), now).windows.single().usedPercent, 1e-9)
        assertEquals(emptyList<Any>(), CopilotClient.map(body, CopilotUnit.AI_CREDITS, CopilotAllowance(CopilotPlan.CUSTOM, null), now).windows)
    }
}
