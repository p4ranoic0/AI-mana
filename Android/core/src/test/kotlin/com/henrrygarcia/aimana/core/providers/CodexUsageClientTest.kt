package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class CodexUsageClientTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val ok = """{"rate_limit":{"primary_window":{"used_percent":5,"reset_at":1799560800,"limit_window_seconds":18000}}}"""

    private suspend fun expectError(block: suspend () -> Unit): UsageError =
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }

    @Test fun mapsParityFixture() {
        val fixture = parityFixture("codex-usage-response.json")
        val usage = CodexUsageClient.map(fixture["response"].toString(), Instant.parse(fixture["now"]!!.jsonPrimitive.content))
        val expected = fixture["expected"] as JsonObject
        assertMatchesExpected(usage, expected)
        assertEquals(expected["plan"]!!.jsonPrimitive.content, usage.plan)
    }

    @Test fun classifiesByDurationNotSlot() {
        val body = """{"rate_limit":{"primary_window":{"used_percent":70,"reset_at":1799899200,"limit_window_seconds":604800},
            "secondary_window":{"used_percent":9,"reset_at":1799560800,"limit_window_seconds":18000}}}"""
        assertEquals(listOf("session" to 9.0, "weekly" to 70.0), CodexUsageClient.map(body, now).windows.map { it.kind to it.usedPercent })
    }

    @Test fun unknownDurationsFillSessionThenWeekly() {
        val body = """{"rate_limit":{"primary_window":{"used_percent":1,"reset_at":1799560800,"limit_window_seconds":7200},
            "secondary_window":{"used_percent":2,"reset_at":1799899200,"limit_window_seconds":2592000}}}"""
        assertEquals(listOf("session" to 120, "weekly" to 43200), CodexUsageClient.map(body, now).windows.map { it.kind to it.windowMinutes })
    }

    @Test fun noWindowsIsDecoding() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, """{"rate_limit":{}}""")))
        assertEquals(UsageError.Decoding, expectError { CodexUsageClient(transport, FixedTokens(), { now }).fetch() })
    }

    @Test fun accountHeaderOnlyWhenPresent() = runBlocking {
        val withAccount = MockTransport(mutableListOf(reply(200, ok)))
        CodexUsageClient(withAccount, FixedTokens(AccessCredential("T", "acct-1")), { now }).fetch()
        assertEquals("acct-1", withAccount.requests.single().headers["ChatGPT-Account-Id"])
        assertEquals("https://chatgpt.com/backend-api/wham/usage", withAccount.requests.single().url)
        assertEquals("AImana", withAccount.requests.single().headers["User-Agent"])
        val without = MockTransport(mutableListOf(reply(200, ok)))
        CodexUsageClient(without, FixedTokens(AccessCredential("T")), { now }).fetch()
        assertFalse(without.requests.single().headers.containsKey("ChatGPT-Account-Id"))
    }

    @Test fun revokedBeforeReadingCredentialsNeverReadsThem() = runBlocking {
        var read = false
        val tokens = AccessTokenSource { read = true; AccessCredential("T") }
        val transport = MockTransport(mutableListOf(reply(200, ok)))
        expectError { CodexUsageClient(transport, tokens, { now }, isAllowed = { false }).fetch() }
        assertFalse(read)
        assertEquals(0, transport.requests.size)
    }

    @Test fun rejectedIsUnauthenticated() = runBlocking {
        for (status in listOf(401, 403)) {
            val transport = MockTransport(mutableListOf(reply(status)))
            assertEquals(UsageError.Unauthenticated, expectError { CodexUsageClient(transport, FixedTokens(), { now }).fetch() })
        }
    }

    @Test fun rateLimitBlocksTheSharedGate() = runBlocking {
        val store = InMemoryKeyValueStore()
        val transport = MockTransport(mutableListOf(reply(429, headers = mapOf("Retry-After" to "60"))))
        expectError { CodexUsageClient(transport, FixedTokens(), { now }, BackoffGate.shared("codex", store)).fetch() }
        assertEquals(UsageError.RateLimited(now.plusSeconds(60)),
                     expectError { CodexUsageClient(transport, FixedTokens(), { now }, BackoffGate.shared("codex", store)).fetch() })
        assertEquals(1, transport.requests.size)
    }
}
