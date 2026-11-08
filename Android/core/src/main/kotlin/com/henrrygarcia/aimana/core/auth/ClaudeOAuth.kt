package com.henrrygarcia.aimana.core.auth

import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import com.henrrygarcia.aimana.core.providers.UsageError
import java.io.IOException
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put

/// This device's own Claude session (not the computer's CLI session). Tokens never appear in logs.
data class ClaudeSession(val accessToken: String, override val refreshToken: String, override val expiresAt: Instant) : RotatingSession {
    override fun toString() = "ClaudeSession(expiresAt=$expiresAt)"
}

data class ClaudeLoginRequest(val url: String, val verifier: String, val state: String) {
    override fun toString() = "ClaudeLoginRequest(url=$url)"
}

/// Claude sign-in on the phone: PKCE, and the user pastes the `code#state` the page shows. Same values as the Swift
/// `ClaudeOAuth` (AImanaSignIn/Auth/ClaudeOAuth.swift).
object ClaudeOAuth {
    const val CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    const val REDIRECT_URI = "https://platform.claude.com/oauth/code/callback"
    const val TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
    const val SCOPE = "user:profile"

    internal fun base64Url(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    private fun random(bytes: Int, random: SecureRandom) = base64Url(ByteArray(bytes).also(random::nextBytes))

    fun challenge(verifier: String): String = base64Url(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))

    fun beginLogin(random: SecureRandom = SecureRandom()): ClaudeLoginRequest {
        val verifier = random(32, random)
        val state = random(24, random)
        val query = listOf("code" to "true", "client_id" to CLIENT_ID, "response_type" to "code", "redirect_uri" to REDIRECT_URI,
                           "scope" to SCOPE, "code_challenge" to challenge(verifier), "code_challenge_method" to "S256", "state" to state)
            .joinToString("&") { (k, v) -> "$k=${URLEncoder.encode(v, "UTF-8")}" }
        return ClaudeLoginRequest("https://claude.ai/oauth/authorize?$query", verifier, state)
    }

    /// The page shows `code#state`; the state must match what this device generated.
    fun parsePastedCode(raw: String, expectedState: String): String {
        val parts = raw.trim().split("#", limit = 2)
        if (parts.size != 2 || parts[0].isEmpty() || parts[1] != expectedState) throw UsageError.Unauthenticated
        return parts[0]
    }

    suspend fun exchange(code: String, request: ClaudeLoginRequest, transport: HttpTransport, now: Instant = Instant.now()) =
        token(mapOf("grant_type" to "authorization_code", "code" to code, "redirect_uri" to REDIRECT_URI, "client_id" to CLIENT_ID,
                    "code_verifier" to request.verifier, "state" to request.state), transport, now, fallbackRefresh = null)

    suspend fun refresh(session: ClaudeSession, transport: HttpTransport, now: Instant = Instant.now()) =
        token(mapOf("grant_type" to "refresh_token", "refresh_token" to session.refreshToken, "client_id" to CLIENT_ID),
              transport, now, fallbackRefresh = session.refreshToken)

    private suspend fun token(body: Map<String, String>, transport: HttpTransport, now: Instant, fallbackRefresh: String?): ClaudeSession {
        val json = buildJsonObject { body.forEach { (k, v) -> put(k, v) } }.toString()
        val response: HttpResponse = try {
            transport.send(HttpRequest(TOKEN_URL, mapOf("Content-Type" to "application/json", "Accept" to "application/json",
                                                        "User-Agent" to "AImana/1.0"), method = "POST", body = json))
        } catch (e: UsageError) {
            throw e
        } catch (e: IOException) {
            throw UsageError.Network
        }
        return when (response.status) {
            200 -> {
                val root = runCatching { Json.parseToJsonElement(response.body) as JsonObject }.getOrNull() ?: throw UsageError.Decoding
                fun str(key: String) = (root[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                val access = str("access_token")?.takeIf { it.isNotEmpty() } ?: throw UsageError.Decoding
                val refresh = str("refresh_token") ?: fallbackRefresh ?: throw UsageError.Decoding
                val lifetime = (root["expires_in"] as? JsonPrimitive)?.doubleOrNull ?: throw UsageError.Decoding
                ClaudeSession(access, refresh, now.plusMillis((lifetime * 1000).toLong()))
            }
            400, 401, 403 -> throw UsageError.Unauthenticated
            429 -> throw UsageError.RateLimited(RetryAfter.until(response.headers, now))
            else -> throw UsageError.Server(response.status)
        }
    }
}
