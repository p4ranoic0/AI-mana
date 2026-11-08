package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageDetail
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/// OpenRouter through its official API with the user's own key. Mirrors the Swift `OpenRouterProvider`:
/// `GET /api/v1/key` (spend, credit limit, free-model allowance) and, best effort, `GET /api/v1/credits`
/// (management keys only; a 401/403 there is remembered for that key).
class OpenRouterClient(
    private val transport: HttpTransport,
    private val tokens: AccessTokenSource,
    private val clock: () -> Instant = Instant::now,
    private val gate: BackoffGate = BackoffGate(),
) {
    @Volatile private var creditsDeniedKey: String? = null

    suspend fun fetch(): UsageInfo {
        val now = clock()
        gate.check(now)?.let { throw UsageError.RateLimited(it) }
        val token = tokens.credentials().token
        val response = sendBearer(transport, KEY_URL, token, mapOf("Accept" to "application/json"))
        return when (response.status) {
            200 -> map(response.body, credits(token), now)
            401, 403 -> throw UsageError.Unauthenticated
            429 -> {
                val until = RetryAfter.until(response.headers, now)
                gate.block(until)
                throw UsageError.RateLimited(until)
            }
            else -> throw UsageError.Server(response.status)
        }
    }

    /// Null when the key may not read account credits or the call fails; never fails the whole reading.
    private suspend fun credits(token: String): String? {
        if (token == creditsDeniedKey) return null
        val response = try {
            sendBearer(transport, CREDITS_URL, token, mapOf("Accept" to "application/json"))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return null
        }
        return when (response.status) {
            200 -> response.body
            401, 403 -> { creditsDeniedKey = token; null }
            else -> null
        }
    }

    /// `limit_reset` values. Periods are UTC; weeks run Monday to Sunday.
    enum class ResetPeriod(val wire: String) {
        DAILY("daily"), WEEKLY("weekly"), MONTHLY("monthly");

        fun period(now: Instant): Pair<Instant, Instant> {
            val day = now.atZone(ZoneOffset.UTC).truncatedTo(ChronoUnit.DAYS)
            val start = when (this) {
                DAILY -> day
                WEEKLY -> day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                MONTHLY -> day.withDayOfMonth(1)
            }
            val end = when (this) {
                DAILY -> start.plusDays(1)
                WEEKLY -> start.plusWeeks(1)
                MONTHLY -> start.plusMonths(1)
            }
            return start.toInstant() to end.toInstant()
        }

        companion object { fun fromWire(raw: String?) = entries.firstOrNull { it.wire == raw } }
    }

    companion object {
        const val PROVIDER_ID = "openrouter"
        const val NAME = "OpenRouter"
        private const val KEY_URL = "https://openrouter.ai/api/v1/key"
        private const val CREDITS_URL = "https://openrouter.ai/api/v1/credits"

        suspend fun validate(key: String, transport: HttpTransport): UsageInfo = OpenRouterClient(transport, FixedKey(key)).fetch()

        // MARK: Mapping (pure; parity with OpenRouterProvider.map via AImana/Fixtures/parity/balances/openrouter.json)

        private fun JsonObject.finite(key: String) = num(key)?.takeIf { it.isFinite() }

        /// A field that must be a number or absent; anything else makes the whole object unreadable (Swift `Double?`).
        private fun JsonObject.strictNum(key: String): Result<Double?> {
            val p = this[key] ?: return Result.success(null)
            if (p is kotlinx.serialization.json.JsonNull) return Result.success(null)
            val value = (p as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()
            return if (value != null) Result.success(value) else Result.failure(IllegalArgumentException())
        }

        fun map(key: String, credits: String?, now: Instant): UsageInfo {
            val info = parseObject(key).obj("data") ?: throw UsageError.Decoding
            val windows = mutableListOf<UsageWindow>()

            // Credit limit of this key: share spent in the current reset period (or ever, when it never resets).
            val limit = info.finite("limit")
            if (limit != null && limit > 0) {
                val reset = ResetPeriod.fromWire(info.str("limit_reset"))
                val periodUsage = when (reset) {
                    ResetPeriod.DAILY -> info.finite("usage_daily")
                    ResetPeriod.WEEKLY -> info.finite("usage_weekly")
                    ResetPeriod.MONTHLY -> info.finite("usage_monthly")
                    null -> info.finite("usage")
                }
                val spent = info.finite("limit_remaining")?.let { limit - it } ?: periodUsage
                if (spent != null) {
                    val period = reset?.period(now)
                    windows += UsageWindow("spend-limit", maxOf(0.0, spent) / limit * 100,
                                           period?.let { Duration.between(it.first, it.second).toMinutes().toInt() }, period?.second)
                }
            }

            // Free-model requests per UTC day. Only worth a lane when they matter: free tier, used today, or nothing else.
            val isFreeTier = (info["is_free_tier"] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: false
            val free = info.obj("free_model_daily_requests")
            if (free != null) {
                val used = free.strictNum("used")
                val freeLimit = free.strictNum("limit")
                val remaining = free.strictNum("remaining")
                if (used.isSuccess && freeLimit.isSuccess && remaining.isSuccess) {
                    val l = freeLimit.getOrNull()
                    if (l != null && l.isFinite() && l > 0) {
                        val u = used.getOrNull() ?: remaining.getOrNull()?.let { l - it }
                        if (u != null && u.isFinite() && (isFreeTier || u > 0 || windows.isEmpty())) {
                            val day = ResetPeriod.DAILY.period(now)
                            windows += UsageWindow("free-requests", maxOf(0.0, u) / l * 100, 1440, day.second)
                        }
                    }
                }
            }

            val details = mutableListOf<UsageDetail>()
            credits?.let { runCatching { parseObject(it).obj("data") }.getOrNull() }?.let { account ->
                val total = account.num("total_credits")
                val usage = account.num("total_usage")
                if (total != null && usage != null && total.isFinite() && usage.isFinite()) {
                    details += UsageDetail("creditBalance", total - usage, total, "USD", usage)
                }
            }
            info.finite("usage_monthly")?.let { details += UsageDetail("monthlySpend", 0.0, currency = "USD", used = it) }

            return UsageInfo(PROVIDER_ID, NAME, windows, if (isFreeTier) "Free" else null, now, details)
        }
    }
}
