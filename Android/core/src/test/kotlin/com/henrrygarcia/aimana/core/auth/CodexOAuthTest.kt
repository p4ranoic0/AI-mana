package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.providers.MockTransport
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.providers.reply
import com.henrrygarcia.aimana.core.storage.InMemoryCredentialStore
import java.time.Duration
import java.time.Instant
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CodexOAuthTest {
    private val now = Instant.parse("2027-01-10T00:00:00Z")
    private fun jwt(claims: String): String {
        val enc = Base64.getUrlEncoder().withoutPadding()
        return enc.encodeToString("""{"alg":"none"}""".toByteArray()) + "." + enc.encodeToString(claims.toByteArray()) + ".sig"
    }
    private val idToken = jwt("""{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-1","chatgpt_plan_type":"plus"}}""")
    private val tokenBody = """{"access_token":"A","refresh_token":"R","id_token":"$idToken","expires_in":3600}"""
    private val device = CodexDeviceCode("https://auth.openai.com/codex/device", "ABCD-1234", "dev-1", Duration.ofSeconds(1), now.plusSeconds(900))

    @Test fun intervalAcceptsStringOrNumber() = runBlocking {
        for (interval in listOf("\"7\"", "7")) {
            val transport = MockTransport(mutableListOf(reply(200, """{"device_auth_id":"d","user_code":"U-1","interval":$interval}""")))
            val code = CodexOAuth.requestDeviceCode(transport, now)
            assertEquals(Duration.ofSeconds(7), code.interval)
            assertEquals(now.plusSeconds(900), code.expiresAt)
        }
    }

    @Test fun deviceCodeRefusedIsUnavailable() = runBlocking {
        try { CodexOAuth.requestDeviceCode(MockTransport(mutableListOf(reply(404))), now); fail() }
        catch (e: CodexLoginException) { assertEquals(CodexLoginException.Reason.DEVICE_CODE_UNAVAILABLE, e.reason) }
    }

    @Test fun pollsUntilApprovedThenRedeemsFormEncoded() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(403), reply(200, """{"authorization_code":"C+/=","code_verifier":"V"}"""), reply(200, tokenBody)))
        val session = CodexOAuth.completeDeviceLogin(device, transport, { now }, sleep = { })
        assertEquals(3, transport.requests.size)
        val exchange = transport.requests[2]
        assertEquals("application/x-www-form-urlencoded", exchange.headers["Content-Type"])
        assertEquals("grant_type=authorization_code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code=C%2B%2F%3D" +
                     "&redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback&code_verifier=V", exchange.body)
        assertEquals("acct-1", session.accountID)
        assertEquals("plus", session.plan)
    }

    @Test fun pollingStopsOnCancel() = runBlocking {
        val transport = MockTransport(MutableList(100) { reply(403) })
        val login = async { CodexOAuth.completeDeviceLogin(device, transport, { now }, sleep = { delay(20) }) }
        delay(70)
        login.cancel()
        try { login.await(); fail() } catch (e: CancellationException) { }
        val count = transport.requests.size
        delay(100)
        assertEquals(count, transport.requests.size)
    }

    @Test fun expiredCodeFails() = runBlocking {
        val expiring = device.copy(expiresAt = now)
        try { CodexOAuth.completeDeviceLogin(expiring, MockTransport(mutableListOf(reply(403))), { now }, sleep = { }); fail() }
        catch (e: CodexLoginException) { assertEquals(CodexLoginException.Reason.EXPIRED, e.reason) }
    }

    @Test fun refreshIsJsonAndKeepsAccountWithoutIdToken() = runBlocking {
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"A2","refresh_token":"R2","expires_in":60}""")))
        val renewed = CodexOAuth.refresh(CodexSession("A", "R", "acct-1", "plus", now), transport, now)
        val body = Json.parseToJsonElement(transport.requests.single().body!!).jsonObject
        assertEquals("refresh_token", body["grant_type"]!!.jsonPrimitive.content)
        assertEquals("application/json", transport.requests.single().headers["Content-Type"])
        assertEquals("acct-1", renewed.accountID)
        assertEquals("R2", renewed.refreshToken)
    }

    @Test fun expiryFromAccessTokenWhenNoExpiresIn() = runBlocking {
        val access = jwt("""{"exp":${now.plusSeconds(1800).epochSecond}}""")
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"$access","refresh_token":"R"}""")))
        assertEquals(now.plusSeconds(1800), CodexOAuth.refresh(CodexSession("A", "R", null, null, now), transport, now).expiresAt)
    }

    @Test fun redirectParserAcceptsFullUrlOrQuery() {
        val login = CodexOAuth.beginBrowserLogin()
        assertTrue(login.url.startsWith("https://auth.openai.com/oauth/authorize?"))
        assertTrue(login.url.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"))
        assertEquals("CODE", CodexOAuth.parsePastedRedirect("http://127.0.0.1:1455/auth/callback?code=CODE&state=${login.state}", login.state))
        assertEquals("CODE", CodexOAuth.parsePastedRedirect("code=CODE&state=${login.state}", login.state))
        try { CodexOAuth.parsePastedRedirect("code=CODE&state=other", login.state); fail() } catch (e: UsageError) { }
    }

    @Test fun phoneTokensRenewWithinFiveMinutes() = runBlocking {
        val store = InMemoryCredentialStore()
        store.write(CodexSessionCodec.encode(CodexSession("A", "R", "acct-1", null, now.plusSeconds(200))), PhoneCodexTokens.STORE_KEY)
        val transport = MockTransport(mutableListOf(reply(200, """{"access_token":"A2","refresh_token":"R2","expires_in":3600}""")))
        val credential = PhoneCodexTokens(store, transport, { now }).credentials()
        assertEquals("A2", credential.token)
        assertEquals("acct-1", credential.accountID)
    }
}
