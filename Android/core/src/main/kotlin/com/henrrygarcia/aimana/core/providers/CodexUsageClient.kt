package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageDetail
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import java.io.IOException
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/// OpenAI Codex usage via `GET chatgpt.com/backend-api/wham/usage` (unofficial). Mirrors the Swift `CodexProvider`.
class CodexUsageClient(
    private val transport: HttpTransport,
    private val tokens: AccessTokenSource,
    private val clock: () -> Instant = Instant::now,
    private val gate: BackoffGate = BackoffGate(),
    /// The user's consent, asked again before reading credentials and before the request.
    private val isAllowed: () -> Boolean = { true },
) {
    suspend fun fetch(): UsageInfo {
        val now = clock()
        gate.check(now)?.let { throw UsageError.RateLimited(it) }
        if (!isAllowed()) throw UsageError.RelayUnavailable
        val credential = tokens.credentials()
        if (!isAllowed()) throw UsageError.RelayUnavailable
        val headers = buildMap {
            put("Authorization", "Bearer ${credential.token}")
            put("Accept", "application/json")
            put("User-Agent", "AImana")
            credential.accountID?.takeIf { it.isNotEmpty() }?.let { put("ChatGPT-Account-Id", it) }
        }
        val response = try {
            transport.send(HttpRequest(URL, headers))
        } catch (e: UsageError) {
            throw e
        } catch (e: IOException) {
            throw UsageError.Network
        }
        return when (response.status) {
            200 -> map(response.body, now)
            401, 403 -> throw UsageError.Unauthenticated
            429 -> {
                val until = RetryAfter.until(response.headers, now)
                gate.block(until)
                throw UsageError.RateLimited(until)
            }
            else -> throw UsageError.Server(response.status)
        }
    }

    companion object {
        private const val URL = "https://chatgpt.com/backend-api/wham/usage"

        private data class Slot(val minutes: Int, val used: Double, val reset: Double)

        private fun slot(raw: JsonObject?): Slot? {
            raw ?: return null
            val used = raw.num("used_percent")?.takeIf { it.isFinite() } ?: return null
            val reset = raw.num("reset_at")?.takeIf { it.isFinite() } ?: return null
            val seconds = raw.num("limit_window_seconds")?.takeIf { it.isFinite() } ?: return null
            return Slot((seconds / 60).toInt(), used, reset)
        }

        private fun instant(seconds: Double): Instant =
            Instant.ofEpochSecond(seconds.toLong(), ((seconds - seconds.toLong()) * 1e9).toLong())

        // MARK: Mapping (pure; parity with CodexProvider.map via AImana/Fixtures/parity/codex-usage-response.json)

        fun map(body: String, now: Instant): UsageInfo {
            val root = runCatching { Json.parseToJsonElement(body) as JsonObject }.getOrNull() ?: throw UsageError.Decoding
            val limit = root.obj("rate_limit") ?: throw UsageError.Decoding
            if (limit["primary_window"] !is JsonObject && limit["secondary_window"] !is JsonObject) throw UsageError.Decoding
            // The API does not guarantee which slot holds which lane: classify by duration (300 = session, 10080 = weekly).
            var session: UsageWindow? = null
            var weekly: UsageWindow? = null
            val unknown = mutableListOf<Slot>()
            for (s in listOfNotNull(slot(limit.obj("primary_window")), slot(limit.obj("secondary_window")))) {
                when (s.minutes) {
                    300 -> session = UsageWindow("session", s.used, 300, instant(s.reset))
                    10080 -> weekly = UsageWindow("weekly", s.used, 10080, instant(s.reset))
                    else -> unknown += s
                }
            }
            // Unrecognised durations keep CodexBar's slot semantics: first fills session, then weekly.
            for (s in unknown) {
                if (session == null) session = UsageWindow("session", s.used, s.minutes, instant(s.reset))
                else if (weekly == null) weekly = UsageWindow("weekly", s.used, s.minutes, instant(s.reset))
            }
            val windows = listOfNotNull(session, weekly).toMutableList()
            if (windows.isEmpty()) throw UsageError.Decoding
            windows += additionalWindows((root["additional_rate_limits"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject })
            val details = mutableListOf<UsageDetail>()
            root.obj("rate_limit_reset_credits")?.let { resets ->
                val count = (resets["available_count"] as? JsonPrimitive)?.intOrNull
                if (count != null && count > 0) {
                    val usable = (resets["applicable_available_count"] as? JsonPrimitive)?.intOrNull?.toDouble()
                    details += UsageDetail("resetCredits", count.toDouble(), usable = usable)
                }
            }
            root.obj("credits")?.let { credits ->
                val has = (credits["has_credits"] as? JsonPrimitive)?.booleanOrNull
                val unlimited = (credits["unlimited"] as? JsonPrimitive)?.booleanOrNull
                val balance = credits.numOrString("balance")
                if (has == true && unlimited != true && balance != null && balance.isFinite() && balance > 0) {
                    details += UsageDetail("creditBalance", balance, currency = "USD")
                }
            }
            return UsageInfo("codex", "OpenAI Codex", windows, root.str("plan_type"), now, details)
        }

        /// Extra lanes per additional limit, named after it: windows shorter than a day become `model-session:`, longer
        /// ones `model:`. They never replace the main lanes. Malformed entries are skipped.
        private fun additionalWindows(limits: List<JsonObject>): List<UsageWindow> {
            val result = mutableListOf<UsageWindow>()
            for (limit in limits) {
                val name = (limit.str("limit_name") ?: limit.str("metered_feature") ?: "").trim()
                val rate = limit.obj("rate_limit")
                if (name.isEmpty() || rate == null) continue
                for (raw in listOfNotNull(rate.obj("primary_window"), rate.obj("secondary_window"))) {
                    val s = slot(raw) ?: continue
                    val seconds = raw.num("limit_window_seconds") ?: continue
                    if (seconds <= 0) continue
                    val kind = if (s.minutes < 1440) "model-session:$name" else "model:$name"
                    if (result.any { it.kind == kind }) continue
                    result += UsageWindow(kind, s.used, s.minutes, if (s.reset > 0) instant(s.reset) else null)
                }
            }
            return result
        }
    }
}
