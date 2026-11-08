package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageDetail
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

/// The Copilot plan the user says they have; mirrors the Swift `CopilotPlan` (same wire values and allowances).
enum class CopilotPlan(val wire: String, val includedCredits: Double?, val legacyPremiumRequests: Double?, val badge: String?) {
    PRO("pro", 1_500.0, 300.0, "Pro"),
    PRO_PLUS("pro-plus", 7_000.0, 1_500.0, "Pro+"),
    MAX("max", 20_000.0, null, "Max"),
    BUSINESS("business", 1_900.0, null, "Business"),
    ENTERPRISE("enterprise", 3_900.0, null, "Enterprise"),
    CUSTOM("custom", null, null, null);

    companion object {
        fun fromWire(raw: String?) = entries.firstOrNull { it.wire == raw }
        /// Same names as the Swift `CopilotPreferences`.
        const val PLAN_KEY = "copilot.plan"
        const val CUSTOM_USD_KEY = "copilot.customUSD"
    }
}

/// What a reading is measured against: the chosen plan, and for `CUSTOM` the monthly amount in US dollars.
data class CopilotAllowance(val plan: CopilotPlan, val customUSD: Double? = null) {
    /// Included AI credits in US dollars (1 credit = US$0.01). Null when there is no usable amount.
    val includedUSD: Double? get() = plan.includedCredits?.let { it / 100 } ?: customUSD?.takeIf { it.isFinite() && it > 0 }
}

enum class CopilotUnit { AI_CREDITS, PREMIUM_REQUESTS }

/// GitHub Copilot usage through GitHub's official billing REST API with the user's own token. Mirrors the Swift
/// `CopilotProvider`: `GET /user` once per token, then this UTC month's AI-credit report (legacy premium-request
/// report only on 404).
class CopilotClient(
    private val transport: HttpTransport,
    private val tokens: AccessTokenSource,
    private val allowance: () -> CopilotAllowance,
    private val clock: () -> Instant = Instant::now,
    private val gate: BackoffGate = BackoffGate(),
) {
    private var memo: Pair<String, String>? = null   // token → login

    suspend fun fetch(): UsageInfo {
        val now = clock()
        gate.check(now)?.let { throw UsageError.RateLimited(it) }
        val token = tokens.credentials().token
        val login = login(token, now)
        val month = utcMonth(now)
        val response = get(reportURL(login, "ai_credit", month.year, month.month), token)
        if (response.status == 404) {
            val legacy = get(reportURL(login, "premium_request", month.year, month.month), token)
            if (legacy.status == 404) throw UsageError.Decoding   // no Copilot report here
            check(legacy, token, now)
            return map(legacy.body, CopilotUnit.PREMIUM_REQUESTS, allowance(), now)
        }
        check(response, token, now)
        return map(response.body, CopilotUnit.AI_CREDITS, allowance(), now)
    }

    private suspend fun login(token: String, now: Instant): String {
        synchronized(this) { memo?.takeIf { it.first == token }?.let { return it.second } }
        val response = get("$API_BASE/user", token)
        check(response, token, now)
        val found = login(response.body) ?: throw UsageError.Decoding
        synchronized(this) { memo = token to found }
        return found
    }

    /// 401 → unauthenticated. 403/429 with GitHub's rate-limit signals → rateLimited; any other 403 → unauthenticated.
    private fun check(response: HttpResponse, token: String, now: Instant) {
        val status = response.status
        if (status == 200) return
        if (status == 429 || (status == 403 && isRateLimit(response))) {
            val until = rateLimitReset(response, now)
            gate.block(until)
            throw UsageError.RateLimited(until)
        }
        when (status) {
            401, 403 -> {
                synchronized(this) { if (memo?.first == token) memo = null }
                throw UsageError.Unauthenticated
            }
            404 -> throw UsageError.Decoding
            else -> throw UsageError.Server(status)
        }
    }

    private suspend fun get(url: String, token: String) =
        sendBearer(transport, url, token, mapOf("Accept" to "application/vnd.github+json", "X-GitHub-Api-Version" to API_VERSION))

    data class UtcMonth(val year: Int, val month: Int, val start: Instant, val end: Instant)

    companion object {
        const val PROVIDER_ID = "copilot"
        const val NAME = "GitHub Copilot"
        private const val API_BASE = "https://api.github.com"
        const val API_VERSION = "2026-03-10"

        suspend fun validate(key: String, allowance: CopilotAllowance, transport: HttpTransport): UsageInfo =
            CopilotClient(transport, FixedKey(key), { allowance }).fetch()

        internal fun isRateLimit(response: HttpResponse) =
            response.header("x-ratelimit-remaining") == "0" || response.header("retry-after") != null

        /// `retry-after` first, then `x-ratelimit-reset` (UTC epoch seconds), else a minute from now.
        internal fun rateLimitReset(response: HttpResponse, now: Instant): Instant {
            if (response.header("retry-after") == null) {
                val epoch = response.header("x-ratelimit-reset")?.toDoubleOrNull()
                if (epoch != null && epoch.isFinite() && epoch > now.epochSecond + now.nano / 1e9) {
                    return Instant.ofEpochMilli((epoch * 1000).toLong())
                }
            }
            return RetryAfter.until(response.headers, now)
        }

        internal fun reportURL(login: String, report: String, year: Int, month: Int) =
            "$API_BASE/users/${PathSegment.encode(login)}/settings/billing/$report/usage?year=$year&month=$month"

        internal fun login(body: String): String? =
            runCatching { parseObject(body) }.getOrNull()?.str("login")?.trim()?.takeIf { it.isNotEmpty() }

        /// The UTC calendar month containing `now`. AI credits and legacy premium requests both reset at 00:00 UTC on the 1st.
        fun utcMonth(now: Instant): UtcMonth {
            val start = now.atZone(ZoneOffset.UTC).truncatedTo(ChronoUnit.DAYS).withDayOfMonth(1)
            return UtcMonth(start.year, start.monthValue, start.toInstant(), start.plusMonths(1).toInstant())
        }

        // MARK: Mapping (pure; parity with CopilotProvider.map via AImana/Fixtures/parity/balances/copilot.json)

        fun map(report: String, unit: CopilotUnit, allowance: CopilotAllowance, now: Instant): UsageInfo {
            val items = (parseObject(report)["usageItems"] as? JsonArray ?: throw UsageError.Decoding).mapNotNull { it as? JsonObject }
                .filter { item ->
                    when (unit) {
                        CopilotUnit.AI_CREDITS -> true
                        // The legacy report is narrowed to Copilot request items.
                        CopilotUnit.PREMIUM_REQUESTS -> {
                            val product = item.str("product")?.lowercase().orEmpty()
                            val unitType = item.str("unitType")?.lowercase() ?: "requests"
                            product.contains("copilot") && unitType == "requests"
                        }
                    }
                }
            fun JsonObject.finite(key: String) = num(key)?.takeIf { it.isFinite() } ?: 0.0
            val gross = items.fold(0.0) { sum, item -> sum + item.finite("grossAmount") }
            val net = items.fold(0.0) { sum, item -> sum + item.finite("netAmount") }
            val month = utcMonth(now)
            val minutes = Duration.between(month.start, month.end).toMinutes().toInt()

            val windows = mutableListOf<UsageWindow>()
            when (unit) {
                CopilotUnit.AI_CREDITS -> allowance.includedUSD?.takeIf { it > 0 }?.let { included ->
                    windows += UsageWindow("spend-limit", maxOf(0.0, gross) / included * 100, minutes, month.end)
                }
                CopilotUnit.PREMIUM_REQUESTS -> allowance.plan.legacyPremiumRequests?.let { included ->
                    val requests = items.fold(0.0) { sum, item -> sum + item.finite("grossQuantity") }
                    windows += UsageWindow("spend-limit", maxOf(0.0, requests) / included * 100, minutes, month.end)
                }
            }
            val details = mutableListOf(UsageDetail("monthlySpend", 0.0, currency = "USD", used = maxOf(0.0, gross)))
            if (net > 0.005) details += UsageDetail("extraUsage", 0.0, currency = "USD", used = net)
            return UsageInfo(PROVIDER_ID, NAME, windows, allowance.plan.badge, now, details)
        }
    }
}
