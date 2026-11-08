package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ClaudeUsageClientTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val ok = """{"five_hour":{"utilization":18.0,"resets_at":"2027-01-10T03:00:00Z"}}"""

    private suspend fun expectError(block: suspend () -> Unit): UsageError =
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }

    @Test fun mapsParityFixture() {
        val fixture = parityFixture("claude-usage-response.json")
        val usage = ClaudeUsageClient.map(fixture["response"].toString(), Instant.parse(fixture["now"]!!.jsonPrimitive.content),
                                          fixture["plan"]?.jsonPrimitive?.contentOrNull)
        assertMatchesExpected(usage, fixture["expected"]!! as kotlinx.serialization.json.JsonObject)
        assertEquals("max", usage.plan)
    }

    @Test fun exactHeaders() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, ok)))
        ClaudeUsageClient(transport, FixedTokens(AccessCredential("T")), { now }).fetch()
        val request = transport.requests.single()
        assertEquals("https://api.anthropic.com/api/oauth/usage?cedar_ember=1", request.url)
        assertEquals("Bearer T", request.headers["Authorization"])
        assertEquals("application/json", request.headers["Accept"])
        assertEquals("oauth-2025-04-20", request.headers["anthropic-beta"])
        assertEquals("claude-cli/2.1.0 (external, cli)", request.headers["User-Agent"])
    }

    @Test fun clientsStillSendGet() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, ok)))
        ClaudeUsageClient(transport, FixedTokens(), { now }).fetch()
        assertEquals("GET", transport.requests.single().method)
        assertEquals(null, transport.requests.single().body)
    }

    @Test fun retriesWithoutOptionalQueryOn400() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(400), reply(200, ok)))
        ClaudeUsageClient(transport, FixedTokens(), { now }).fetch()
        assertEquals(2, transport.requests.size)
        assertFalse(transport.requests[1].url.contains("cedar_ember"))
    }

    @Test fun profileScope403IsUnauthenticatedWithoutRetry() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(403, """{"error":"missing user:profile scope"}""")))
        assertEquals(UsageError.Unauthenticated, expectError { ClaudeUsageClient(transport, FixedTokens(), { now }).fetch() })
        assertEquals(1, transport.requests.size)
    }

    @Test fun rateLimitBlocksTheSharedGate() = runBlocking {
        val store = InMemoryKeyValueStore()
        val transport = MockTransport(mutableListOf(reply(429, headers = mapOf("Retry-After" to "120"))))
        val error = expectError { ClaudeUsageClient(transport, FixedTokens(), { now }, BackoffGate.shared("claude", store)).fetch() }
        assertEquals(UsageError.RateLimited(now.plusSeconds(120)), error)
        val again = expectError { ClaudeUsageClient(transport, FixedTokens(), { now.plusSeconds(30) }, BackoffGate.shared("claude", store)).fetch() }
        assertTrue(again is UsageError.RateLimited)
        assertEquals(1, transport.requests.size)
    }

    @Test fun revokedBeforeTheRetrySendsNothingMore() = runBlocking {
        var allowed = true
        val transport = object : com.henrrygarcia.aimana.core.net.HttpTransport {
            val urls = mutableListOf<String>()
            override suspend fun send(request: com.henrrygarcia.aimana.core.net.HttpRequest): com.henrrygarcia.aimana.core.net.HttpResponse {
                urls += request.url
                allowed = false                       // the user turns direct access off while the first request is out
                return reply(400)
            }
        }
        expectError { ClaudeUsageClient(transport, FixedTokens(), { now }, isAllowed = { allowed }).fetch() }
        assertEquals(1, transport.urls.size)
    }

    @Test fun revokedBeforeReadingCredentialsNeverReadsThem() = runBlocking {
        var read = false
        val tokens = AccessTokenSource { read = true; AccessCredential("T") }
        expectError { ClaudeUsageClient(MockTransport(mutableListOf(reply(200, ok))), tokens, { now }, isAllowed = { false }).fetch() }
        assertFalse(read)
    }

    @Test fun serverErrorKeepsStatus() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(503)))
        assertEquals(UsageError.Server(503), expectError { ClaudeUsageClient(transport, FixedTokens(), { now }).fetch() })
    }
}
