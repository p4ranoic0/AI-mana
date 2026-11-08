package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import com.henrrygarcia.aimana.core.providers.AccessCredential
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.CredentialStore
import java.io.IOException
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import kotlin.coroutines.coroutineContext

/// This device's own ChatGPT session; `accountID` goes in `ChatGPT-Account-Id`. Tokens never appear in logs.
data class CodexSession(val accessToken: String, override val refreshToken: String, val accountID: String?, val plan: String?,
                        override val expiresAt: Instant) : RotatingSession {
    override fun toString() = "CodexSession(account=${accountID != null}, plan=$plan, expiresAt=$expiresAt)"
}

/// A pending device-code sign-in: the user opens `verificationURL` and types `userCode`. `deviceAuthID` stays in memory.
data class CodexDeviceCode(val verificationURL: String, val userCode: String, internal val deviceAuthID: String,
                           val interval: Duration, val expiresAt: Instant) {
    override fun toString() = "CodexDeviceCode(userCode=$userCode, expiresAt=$expiresAt)"
}

data class CodexLoginRequest(val url: String, val verifier: String, val state: String) {
    override fun toString() = "CodexLoginRequest(url=$url)"
}

class CodexLoginException(val reason: Reason) : Exception(reason.name) {
    enum class Reason {
        /// `/deviceauth/usercode` refused (device code sign-in is off for the account).
        DEVICE_CODE_UNAVAILABLE,
        /// Not approved before the code expired.
        EXPIRED,
    }
}

/// ChatGPT sign-in as the Codex CLI does it; same values as the Swift `CodexOAuth` (AImanaSignIn/Auth/CodexOAuth.swift).
object CodexOAuth {
    const val ISSUER = "https://auth.openai.com"
    const val CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private const val TOKEN_URL = "$ISSUER/oauth/token"
    private const val USER_CODE_URL = "$ISSUER/api/accounts/deviceauth/usercode"
    private const val DEVICE_TOKEN_URL = "$ISSUER/api/accounts/deviceauth/token"
    const val VERIFICATION_URL = "$ISSUER/codex/device"
    private const val DEVICE_REDIRECT_URI = "$ISSUER/deviceauth/callback"
    const val BROWSER_REDIRECT_URI = "http://127.0.0.1:1455/auth/callback"
    private const val SCOPE = "openid profile email offline_access"
    private val DEVICE_CODE_LIFETIME: Duration = Duration.ofMinutes(15)
    private val FALLBACK_LIFETIME: Duration = Duration.ofHours(1)

    suspend fun requestDeviceCode(transport: HttpTransport, now: Instant = Instant.now()): CodexDeviceCode {
        val response = post(USER_CODE_URL, buildJsonObject { put("client_id", CLIENT_ID) }.toString(), "application/json", transport)
        return when (response.status) {
            200 -> {
                val root = parse(response.body)
                val id = root.str("device_auth_id")?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
                val code = (root.str("user_code") ?: root.str("usercode"))?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
                // The server sends `interval` as a string ("5"); a number works too.
                val raw = root["interval"] as? JsonPrimitive
                val interval = (raw?.doubleOrNull ?: raw?.contentOrNull?.trim()?.toDoubleOrNull() ?: 5.0).coerceAtLeast(0.0)
                val expires = root.str("expires_at")?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
                    ?: now.plus(DEVICE_CODE_LIFETIME)
                CodexDeviceCode(VERIFICATION_URL, code, id, Duration.ofMillis((interval * 1000).toLong()), expires)
            }
            403, 404 -> throw CodexLoginException(CodexLoginException.Reason.DEVICE_CODE_UNAVAILABLE)
            429 -> throw UsageError.RateLimited(RetryAfter.until(response.headers, now))
            else -> throw UsageError.Server(response.status)
        }
    }

    /// Polls at the server's interval until the user approves, then redeems the code. Cancelling stops the polling.
    suspend fun completeDeviceLogin(device: CodexDeviceCode, transport: HttpTransport, clock: () -> Instant = Instant::now,
                                    sleep: suspend (Duration) -> Unit = { delay(it.toMillis()) }): CodexSession {
        while (true) {
            coroutineContext.ensureActive()
            val response = post(DEVICE_TOKEN_URL, buildJsonObject {
                put("device_auth_id", device.deviceAuthID); put("user_code", device.userCode)
            }.toString(), "application/json", transport)
            when (response.status) {
                200 -> {
                    val root = parse(response.body)
                    val code = root.str("authorization_code")?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
                    val verifier = root.str("code_verifier")?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
                    return exchange(code, verifier, DEVICE_REDIRECT_URI, transport, clock())
                }
                403, 404 -> Unit   // not approved yet
                400, 401 -> throw UsageError.Unauthenticated
                else -> throw UsageError.Server(response.status)
            }
            val remaining = Duration.between(clock(), device.expiresAt)
            if (remaining <= Duration.ZERO) throw CodexLoginException(CodexLoginException.Reason.EXPIRED)
            sleep(minOf(maxOf(device.interval, Duration.ofSeconds(1)), remaining))
        }
    }

    // Browser fallback: PKCE with a loopback redirect; the user pastes the unreachable page's address back.

    fun beginBrowserLogin(random: SecureRandom = SecureRandom()): CodexLoginRequest {
        val verifier = ClaudeOAuth.base64Url(ByteArray(64).also(random::nextBytes))
        val state = ClaudeOAuth.base64Url(ByteArray(32).also(random::nextBytes))
        val query = listOf("response_type" to "code", "client_id" to CLIENT_ID, "redirect_uri" to BROWSER_REDIRECT_URI,
                           "scope" to SCOPE, "code_challenge" to ClaudeOAuth.challenge(verifier), "code_challenge_method" to "S256",
                           "id_token_add_organizations" to "true", "codex_cli_simplified_flow" to "true", "state" to state)
            .joinToString("&") { (k, v) -> "$k=${URLEncoder.encode(v, "UTF-8")}" }
        return CodexLoginRequest("$ISSUER/oauth/authorize?$query", verifier, state)
    }

    /// The full address the browser shows, or just its query; the state must match this device's.
    fun parsePastedRedirect(raw: String, expectedState: String): String {
        val trimmed = raw.trim()
        val query = trimmed.substringAfter("?", trimmed).substringBefore("#")
        val items = query.split("&").mapNotNull { pair ->
            val parts = pair.split("=", limit = 2)
            if (parts.size == 2) URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts[1], "UTF-8") else null
        }.toMap()
        val code = items["code"]?.takeIf { it.isNotEmpty() }
        if (code == null || items["state"] != expectedState) throw UsageError.Unauthenticated
        return code
    }

    suspend fun exchange(code: String, request: CodexLoginRequest, transport: HttpTransport, now: Instant = Instant.now()) =
        exchange(code, request.verifier, BROWSER_REDIRECT_URI, transport, now)

    private suspend fun exchange(code: String, verifier: String, redirectURI: String, transport: HttpTransport, now: Instant): CodexSession {
        // The CLI sends the code exchange form-encoded.
        val body = formEncode(listOf("grant_type" to "authorization_code", "client_id" to CLIENT_ID, "code" to code,
                                     "redirect_uri" to redirectURI, "code_verifier" to verifier))
        return token(post(TOKEN_URL, body, "application/x-www-form-urlencoded", transport), now, previous = null)
    }

    suspend fun refresh(session: CodexSession, transport: HttpTransport, now: Instant = Instant.now()): CodexSession {
        // The CLI sends refreshes as JSON.
        val body = buildJsonObject {
            put("grant_type", "refresh_token"); put("client_id", CLIENT_ID); put("refresh_token", session.refreshToken)
        }.toString()
        return token(post(TOKEN_URL, body, "application/json", transport), now, previous = session)
    }

    private fun token(response: HttpResponse, now: Instant, previous: CodexSession?): CodexSession = when (response.status) {
        200 -> {
            val root = parse(response.body)
            val access = root.str("access_token")?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
            val refresh = (root.str("refresh_token") ?: previous?.refreshToken)?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
            // A refresh may omit the id_token; the account it names does not change, so keep the previous one.
            val idClaims = root.str("id_token")?.let(::authClaims)
            val accessClaims = authClaims(access)
            val account = idClaims?.str("chatgpt_account_id") ?: accessClaims?.str("chatgpt_account_id") ?: previous?.accountID
            val plan = idClaims?.str("chatgpt_plan_type") ?: accessClaims?.str("chatgpt_plan_type") ?: previous?.plan
            val lifetime = (root["expires_in"] as? JsonPrimitive)?.doubleOrNull
            val expires = when {
                lifetime != null -> now.plusMillis((lifetime * 1000).toLong())
                else -> (jwtPayload(access)?.get("exp") as? JsonPrimitive)?.doubleOrNull?.let { Instant.ofEpochSecond(it.toLong()) }
                    ?: now.plus(FALLBACK_LIFETIME)
            }
            CodexSession(access, refresh, account, plan, expires)
        }
        400, 401, 403 -> throw UsageError.Unauthenticated
        429 -> throw UsageError.RateLimited(RetryAfter.until(response.headers, now))
        else -> throw UsageError.Server(response.status)
    }

    /// Only RFC 3986 unreserved characters stay bare, so `+`, `&`, `=` and `/` in a code or verifier are never misread.
    fun formEncode(pairs: List<Pair<String, String>>): String {
        fun encode(text: String) = buildString {
            for (byte in text.toByteArray(Charsets.UTF_8)) {
                val c = byte.toInt().toChar()
                if (c.isLetterOrDigit() && c.code < 128 || c in "-._~") append(c) else append("%%%02X".format(byte.toInt() and 0xFF))
            }
        }
        return pairs.joinToString("&") { (k, v) -> "${encode(k)}=${encode(v)}" }
    }

    private suspend fun post(url: String, body: String, contentType: String, transport: HttpTransport): HttpResponse = try {
        transport.send(HttpRequest(url, mapOf("Content-Type" to contentType, "Accept" to "application/json", "User-Agent" to "AImana/1.0"),
                                   method = "POST", body = body))
    } catch (e: CancellationException) {
        throw e
    } catch (e: UsageError) {
        throw e
    } catch (e: IOException) {
        throw UsageError.Network
    }

    private fun parse(body: String): JsonObject = runCatching { Json.parseToJsonElement(body) as JsonObject }.getOrNull() ?: throw UsageError.Decoding

    /// Payload of a JWT, unverified: it only selects the workspace; the server enforces the token's permissions.
    internal fun jwtPayload(jwt: String): JsonObject? {
        val parts = jwt.split(".")
        if (parts.size != 3) return null
        return runCatching {
            val padded = parts[1].padEnd((parts[1].length + 3) / 4 * 4, '=')
            Json.parseToJsonElement(String(Base64.getUrlDecoder().decode(padded))) as JsonObject
        }.getOrNull()
    }

    /// The `https://api.openai.com/auth` claims: `chatgpt_account_id` and `chatgpt_plan_type`.
    private fun authClaims(jwt: String): JsonObject? = jwtPayload(jwt)?.get("https://api.openai.com/auth") as? JsonObject

    private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
}

object CodexSessionCodec : SessionCodec<CodexSession> {
    override fun encode(session: CodexSession) = buildJsonObject {
        put("accessToken", session.accessToken)
        put("refreshToken", session.refreshToken)
        session.accountID?.let { put("accountID", it) }
        session.plan?.let { put("plan", it) }
        put("expiresAt", session.expiresAt.toString())
    }.toString()

    override fun decode(text: String): CodexSession? = runCatching {
        val o = Json.parseToJsonElement(text) as JsonObject
        fun s(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
        CodexSession(s("accessToken")!!, s("refreshToken")!!, s("accountID"), s("plan"), Instant.parse(s("expiresAt")!!))
    }.getOrNull()
}

/// This device's own ChatGPT access token and workspace, renewed within 5 minutes of expiry (as the CLI does).
class PhoneCodexTokens(store: CredentialStore, private val transport: HttpTransport, clock: () -> Instant = Instant::now) : AccessTokenSource {
    private val keeper = SessionKeeper(STORE_KEY, store, clock, RENEW_SKEW, CodexSessionCodec) { session, now ->
        CodexOAuth.refresh(session, transport, now)
    }

    val isSignedIn: Boolean get() = keeper.load() != null

    suspend fun save(session: CodexSession) = keeper.save(session)

    suspend fun signOut() = keeper.delete()

    override suspend fun credentials(): AccessCredential {
        val session = keeper.current()
        return AccessCredential(session.accessToken, session.accountID, session.plan)
    }

    companion object {
        const val STORE_KEY = "codex.phone.session"
        val RENEW_SKEW: Duration = Duration.ofSeconds(300)
    }
}
