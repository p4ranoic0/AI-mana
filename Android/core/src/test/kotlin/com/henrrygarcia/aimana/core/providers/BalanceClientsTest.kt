package com.henrrygarcia.aimana.core.providers

import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class BalanceClientsTest {
    private val now = Instant.parse("2027-01-15T08:00:00Z")

    private fun expectError(block: suspend () -> Unit): UsageError = runBlocking {
        try { block(); fail("expected a UsageError"); throw IllegalStateException() } catch (e: UsageError) { e }
    }

    private fun client(descriptor: BalanceDescriptor, transport: MockTransport, key: String = "sk-test") =
        BalanceClient(descriptor, transport, FixedKey(key), { now })

    private fun checkFixture(descriptor: BalanceDescriptor, name: String, extra: List<Pair<Int, String>> = emptyList()) = runBlocking {
        val fixture = parityFixture("balances/$name")
        val transport = MockTransport((extra.map { reply(it.first, it.second) } + reply(200, fixture["response"].toString())).toMutableList())
        val usage = client(descriptor, transport).fetch()
        assertEquals(descriptor.id, usage.providerID)
        assertMatchesExpected(usage, fixture["expected"] as JsonObject)
        assertNull(usage.plan)
    }

    @Test fun deepSeekMapsParityFixture() = checkFixture(BalanceDescriptor.DEEPSEEK, "deepseek.json")

    @Test fun moonshotMapsParityFixture() = checkFixture(BalanceDescriptor.MOONSHOT, "moonshot.json", listOf(401 to "{}"))

    @Test fun xAIMapsParityFixture() {
        val fixture = parityFixture("balances/xai.json")
        assertEquals(fixture["expectedTeamId"]!!.jsonPrimitive.content, BalanceDecoding.xAITeamID(fixture["validation"].toString()))
        checkFixture(BalanceDescriptor.XAI, "xai.json", listOf(200 to fixture["validation"].toString()))
    }

    @Test fun keyIsTrimmed() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, """{"is_available":true,"balance_infos":[]}""")))
        client(BalanceDescriptor.DEEPSEEK, transport, key = "  sk-abc \n").fetch()
        assertEquals("Bearer sk-abc", transport.requests.single().headers["Authorization"])
        assertEquals(UsageError.Unauthenticated, expectError { client(BalanceDescriptor.DEEPSEEK, MockTransport(mutableListOf()), key = "  ").fetch() })
    }

    @Test fun rejectedKeyIsUnauthenticated() {
        for (status in listOf(401, 403)) {
            assertEquals(UsageError.Unauthenticated, expectError { client(BalanceDescriptor.DEEPSEEK, MockTransport(mutableListOf(reply(status)))).fetch() })
        }
        // Moonshot: rejected by both hosts.
        assertEquals(UsageError.Unauthenticated,
                     expectError { client(BalanceDescriptor.MOONSHOT, MockTransport(mutableListOf(reply(401), reply(401)))).fetch() })
    }

    @Test fun moonshotFallsBackToTheOtherHost() = runBlocking {
        val body = """{"data":{"available_balance":3}}"""
        val transport = MockTransport(mutableListOf(reply(401), reply(200, body), reply(200, body)))
        val moonshot = client(BalanceDescriptor.MOONSHOT, transport)
        assertEquals("CNY", moonshot.fetch().details.single().currency)
        // The region is remembered for this key: the second reading goes straight to the China host.
        moonshot.fetch()
        assertEquals(listOf("api.moonshot.ai", "api.moonshot.cn", "api.moonshot.cn"),
                     transport.requests.map { java.net.URI(it.url).host })
    }

    @Test fun xAIReadsTheTeamOnceAndForgetsItWhenRejected() = runBlocking {
        val validation = """{"teamId":"team/1"}"""
        val balance = """{"total":{"val":"-250"}}"""
        val transport = MockTransport(mutableListOf(reply(200, validation), reply(200, balance), reply(200, balance),
                                                    reply(403), reply(200, validation), reply(200, balance)))
        val xai = client(BalanceDescriptor.XAI, transport)
        assertEquals(2.5, xai.fetch().details.single().remaining, 1e-9)
        xai.fetch()
        assertEquals(UsageError.Unauthenticated, expectError { xai.fetch() })
        xai.fetch()
        assertEquals(listOf("/auth/management-keys/validation", "/v1/billing/teams/team%2F1/prepaid/balance",
                            "/v1/billing/teams/team%2F1/prepaid/balance", "/v1/billing/teams/team%2F1/prepaid/balance",
                            "/auth/management-keys/validation", "/v1/billing/teams/team%2F1/prepaid/balance"),
                     transport.requests.map { java.net.URI(it.url).rawPath })
    }

    @Test fun rateLimitIsRemembered() {
        val transport = MockTransport(mutableListOf(reply(429, headers = mapOf("Retry-After" to "30"))))
        val deepSeek = client(BalanceDescriptor.DEEPSEEK, transport)
        assertEquals(UsageError.RateLimited(now.plusSeconds(30)), expectError { deepSeek.fetch() })
        assertEquals(UsageError.RateLimited(now.plusSeconds(30)), expectError { deepSeek.fetch() })
        assertEquals(1, transport.requests.size)
    }

    @Test fun foreignPayloadsAreDecodingErrors() {
        for (body in listOf("not json", """{"error":{"message":"Authentication Fails"}}""", "[]")) {
            assertEquals(UsageError.Decoding, expectError { BalanceDecoding.deepSeek(body) })
            assertEquals(UsageError.Decoding, expectError { BalanceDecoding.moonshot(body, "USD") })
            assertEquals(UsageError.Decoding, expectError { BalanceDecoding.xAI(body) })
        }
    }

    @Test fun unavailableDeepSeekBalanceIsNotUsable() {
        val detail = BalanceDecoding.deepSeek("""{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.03"}]}""").single()
        assertEquals(0.0, detail.usable)
    }
}
