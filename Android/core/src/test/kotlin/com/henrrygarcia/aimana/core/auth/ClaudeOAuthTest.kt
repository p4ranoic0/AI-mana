package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.providers.MockTransport
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.providers.parityFixture
import com.henrrygarcia.aimana.core.providers.reply
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ClaudeOAuthTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private val request = ClaudeLoginRequest("https://claude.ai/oauth/authorize", verifier = "VERIFIER", state = "STATE")

    private suspend fun expectError(block: suspend () -> Unit): UsageError =
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }

    @Test fun challengeMatchesVectors() {
        for (pair in parityFixture("oauth-vectors.json")["pkce"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(pair["challenge"]!!.jsonPrimitive.content, ClaudeOAuth.challenge(pair["verifier"]!!.jsonPrimitive.content))
        }
    }

    @Test fun parsesCodeHashStateLikeSwift() {
        for (case in parityFixture("oauth-vectors.json")["pastedCode"]!!.jsonArray.map { it.jsonObject }) {
            val expected = case["code"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull
            val actual = runCatching { ClaudeOAuth.parsePastedCode(case["raw"]!!.jsonPrimitive.content, case["state"]!!.jsonPrimitive.content) }.getOrNull()
            assertEquals(case["raw"]!!.jsonPrimitive.content, expected, actual)
        }
    }

    @Test fun beginLoginBuildsTheAuthorizeUrl() {
        val login = ClaudeOAuth.beginLogin()
        assertTrue(login.url.startsWith("https://claude.ai/oauth/authorize?"))
        for (part in listOf("code=true", "client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e", "response_type=code",
                            "redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback", "scope=user%3Aprofile",
                            "code_challenge=${ClaudeOAuth.challenge(login.verifier)}", "code_challenge_method=S256", "state=${login.state}")) {
            assertTrue(part, login.url.contains(part))
        }
    }

    @Test fun exchangeSendsJsonBody() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"A","refresh_token":"R","expires_in":3600}""")))
        val session = ClaudeOAuth.exchange("CODE", request, transport, now)
        val sent = transport.requests.single()
        assertEquals("POST", sent.method)
        assertEquals("https://platform.claude.com/v1/oauth/token", sent.url)
        assertEquals("application/json", sent.headers["Content-Type"])
        assertEquals("AImana/1.0", sent.headers["User-Agent"])
        val body = Json.parseToJsonElement(sent.body!!).jsonObject.mapValues { it.value.jsonPrimitive.content }
        assertEquals(mapOf("grant_type" to "authorization_code", "code" to "CODE", "redirect_uri" to "https://platform.claude.com/oauth/code/callback",
                           "client_id" to "9d1c250a-e61b-44d9-88ed-5944d1962f5e", "code_verifier" to "VERIFIER", "state" to "STATE"), body)
        assertEquals(ClaudeSession("A", "R", now.plusSeconds(3600)), session)
    }

    @Test fun refreshKeepsOldRefreshTokenWhenOmitted() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"A2","expires_in":60}""")))
        val renewed = ClaudeOAuth.refresh(ClaudeSession("A", "R", now), transport, now)
        assertEquals("R", renewed.refreshToken)
        val body = Json.parseToJsonElement(transport.requests.single().body!!).jsonObject
        assertEquals("refresh_token", body["grant_type"]!!.jsonPrimitive.content)
    }

    @Test fun invalidGrantIsUnauthenticated() = runBlocking {
        for (status in listOf(400, 401, 403)) {
            val transport = MockTransport(mutableListOf(reply(status, """{"error":"invalid_grant"}""")))
            assertEquals(UsageError.Unauthenticated, expectError { ClaudeOAuth.refresh(ClaudeSession("A", "R", now), transport, now) })
        }
        val limited = MockTransport(mutableListOf(reply(429, headers = mapOf("Retry-After" to "30"))))
        assertEquals(UsageError.RateLimited(now.plusSeconds(30)), expectError { ClaudeOAuth.refresh(ClaudeSession("A", "R", now), limited, now) })
    }

    @Test fun sessionToStringHidesTokens() {
        assertTrue(!ClaudeSession("SECRET-A", "SECRET-R", now).toString().contains("SECRET"))
    }
}
