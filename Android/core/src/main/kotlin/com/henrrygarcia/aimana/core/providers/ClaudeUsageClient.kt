package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageDetail
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import java.io.IOException
import java.time.Instant
import kotlin.math.max
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/// Claude Code usage via `GET api.anthropic.com/api/oauth/usage` (unofficial). Mirrors the Swift `ClaudeProvider`.
class ClaudeUsageClient(
    private val transport: HttpTransport,
    private val tokens: AccessTokenSource,
    private val clock: () -> Instant = Instant::now,
    private val gate: BackoffGate = BackoffGate(),
    /// The user's consent, asked again before reading credentials and before every request (a retry included).
    private val isAllowed: () -> Boolean = { true },
) {
    private fun requireAllowed() { if (!isAllowed()) throw UsageError.RelayUnavailable }

    suspend fun fetch(): UsageInfo {
        val now = clock()
        gate.check(now)?.let { throw UsageError.RateLimited(it) }
        requireAllowed()
        val credential = tokens.credentials()
        var response = send(credential, optionalQuery = true)
        // Optional query rejected: retry once without it, same credential.
        if (response.status == 400 || (response.status == 403 && !response.body.contains("user:profile"))) {
            response = send(credential, optionalQuery = false)
        }
        return when (response.status) {
            200 -> map(response.body, now, credential.plan)
            401, 403 -> throw UsageError.Unauthenticated
            429 -> {
                val until = RetryAfter.until(response.headers, now)
                gate.block(until)
                throw UsageError.RateLimited(until)
            }
            else -> throw UsageError.Server(response.status)
        }
    }

    private suspend fun send(credential: AccessCredential, optionalQuery: Boolean): HttpResponse = try {
        requireAllowed()
        transport.send(HttpRequest(BASE + if (optionalQuery) "?cedar_ember=1" else "", mapOf(
            "Authorization" to "Bearer ${credential.token}",
            "Accept" to "application/json",
            "anthropic-beta" to "oauth-2025-04-20",
            "User-Agent" to "claude-cli/2.1.0 (external, cli)",
        )))
    } catch (e: UsageError) {
        throw e
    } catch (e: IOException) {
        throw UsageError.Network
    }

    companion object {
        private const val BASE = "https://api.anthropic.com/api/oauth/usage"

        // MARK: Mapping (pure; parity with ClaudeProvider.map via AImana/Fixtures/parity/claude-usage-response.json)

        fun map(body: String, now: Instant, plan: String?): UsageInfo {
            val root = runCatching { Json.parseToJsonElement(body) as JsonObject }.getOrNull() ?: throw UsageError.Decoding
            fun window(key: String, kind: String): UsageWindow? {
                val raw = root.obj(key) ?: return null
                val used = raw.num("utilization")?.takeIf { it.isFinite() } ?: return null
                return UsageWindow(kind, used, if (kind == "session") 300 else 10080, IsoDate.parse(raw.str("resets_at")))
            }
            val windows = listOfNotNull(
                window("five_hour", "session"), window("seven_day", "weekly"),
                window("seven_day_sonnet", "model:Sonnet"), window("seven_day_opus", "model:Opus"),
            ).toMutableList()
            // Model-scoped weekly limits from `limits[]`, without duplicating lanes already mapped above.
            for (entry in (root["limits"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }) {
                val name = entry.obj("scope")?.obj("model")?.str("display_name")?.takeIf { it.isNotEmpty() } ?: continue
                val percent = entry.num("percent")?.takeIf { it.isFinite() } ?: continue
                if (windows.any { it.kind == "model:$name" }) continue
                windows += UsageWindow("model:$name", percent, 10080, IsoDate.parse(entry.str("resets_at")))
            }
            val details = listOfNotNull(root.obj("iguana_necktie")?.let { cloudCredits(it, now) },
                                        root.obj("extra_usage")?.let(::extraUsage))
            // Spend-only accounts (no rate-limit windows) still have something to show when extra usage is on.
            if (windows.isEmpty() && details.none { it.kind == "extraUsage" }) throw UsageError.Decoding
            return UsageInfo("claude", "Claude Code", windows, plan, now, details)
        }

        /// A positive allowance and a balance inside it; locked or expired grants are hidden.
        private fun cloudCredits(raw: JsonObject, now: Instant): UsageDetail? {
            val limit = raw.num("limit_dollars")?.takeIf { it.isFinite() && it > 0 } ?: return null
            val used = raw.num("used_dollars")
            val left = raw.num("remaining_dollars")
            if (used != null && !(used.isFinite() && used >= 0 && used <= limit)) return null
            if (left != null && !(left.isFinite() && left >= 0 && left <= limit)) return null
            val remaining = left ?: used?.let { limit - it } ?: return null
            if (!raw.str("locked_reason").isNullOrBlank()) return null
            val expires = IsoDate.parse(raw.str("resets_at"))
            if (expires != null && !expires.isAfter(now)) return null
            return UsageDetail("cloudCredits", remaining, limit, "USD", expiresAt = expires)
        }

        /// Shown only while enabled; amounts are in cents; a missing or zero cap means "no cap".
        private fun extraUsage(raw: JsonObject): UsageDetail? {
            if ((raw["is_enabled"] as? JsonPrimitive)?.booleanOrNull != true) return null
            val cap = (raw.num("monthly_limit") ?: raw.num("monthly_credit_limit"))?.takeIf { it.isFinite() && it > 0 }?.div(100)
            var used = raw.num("used_credits")?.takeIf { it.isFinite() && it >= 0 }?.div(100)
            val percent = raw.num("utilization")
            if (used == null && cap != null && percent != null && percent.isFinite() && percent >= 0) used = cap * percent / 100
            used ?: return null
            val currency = raw.str("currency")?.takeIf { it.length == 3 }?.uppercase() ?: "USD"
            return UsageDetail("extraUsage", cap?.let { max(0.0, it - used) } ?: 0.0, cap, currency, used)
        }
    }
}

internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
internal fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
/// A JSON number only, like Swift's `Double` decoding.
internal fun JsonObject.num(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
/// A number, or a numeric string (Codex's credit balance arrives as either).
internal fun JsonObject.numOrString(key: String): Double? =
    (this[key] as? JsonPrimitive)?.let { p -> if (p.isString) p.content.trim().toDoubleOrNull() else p.doubleOrNull }
