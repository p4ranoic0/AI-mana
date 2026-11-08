package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageDetail
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.net.RetryAfter
import java.io.IOException
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/// Where each pasted key is stored: the same names as the Swift `CredentialKey` constants.
object CredentialKey {
    const val DEEPSEEK = "deepseek.apiKey"
    const val MOONSHOT = "moonshot.apiKey"
    /// An xAI *management* key (xAI Console → Settings → Management Keys), not an inference key.
    const val XAI = "xai.managementKey"
    const val OPENROUTER = "openrouter.apiKey"
    const val COPILOT = "copilot.githubToken"
}

/// A key typed in Settings (or read from the store). Blank is a missing key.
class FixedKey(private val key: String) : AccessTokenSource {
    override suspend fun credentials(): AccessCredential {
        val trimmed = key.trim()
        if (trimmed.isEmpty()) throw UsageError.Unauthenticated
        return AccessCredential(trimmed)
    }
    override fun toString() = "FixedKey(<redacted>)"
}

/// What sets one prepaid-balance API apart from another. Mirrors the Swift `BalanceDescriptor`.
class BalanceDescriptor internal constructor(
    val id: String,
    val name: String,
    val credentialKey: String,
    internal val route: Route,
    /// Balance response (and the endpoint's currency) to balance entries. Throws `Decoding` for a foreign shape.
    internal val decode: (String, String?) -> List<UsageDetail>,
) {
    internal data class Endpoint(val url: String, val currency: String?)

    internal sealed class Route {
        /// Hosts tried in order: each platform rejects the other's keys with 401, so the first that accepts is the region.
        data class Alternatives(val endpoints: List<Endpoint>) : Route()
        /// The balance URL needs an ID read first with the same key (xAI: the key's team).
        class Scoped(val lookup: String, val scopeID: (String) -> String?, val balance: (String) -> Endpoint) : Route()
    }

    companion object {
        /// DeepSeek: `GET https://api.deepseek.com/user/balance`; amounts are strings, one entry per currency.
        val DEEPSEEK = BalanceDescriptor("deepseek", "DeepSeek", CredentialKey.DEEPSEEK,
            Route.Alternatives(listOf(Endpoint("https://api.deepseek.com/user/balance", null)))) { body, _ -> BalanceDecoding.deepSeek(body) }

        /// Moonshot / Kimi: international host in USD, China host in CNY; the region is found by trying both.
        val MOONSHOT = BalanceDescriptor("moonshot", "Moonshot (Kimi)", CredentialKey.MOONSHOT,
            Route.Alternatives(listOf(Endpoint("https://api.moonshot.ai/v1/users/me/balance", "USD"),
                                      Endpoint("https://api.moonshot.cn/v1/users/me/balance", "CNY")))) { body, currency ->
            BalanceDecoding.moonshot(body, currency ?: "USD")
        }

        /// xAI: the management key's team, then that team's prepaid balance (USD cents, purchases negative).
        val XAI = BalanceDescriptor("xai", "xAI", CredentialKey.XAI,
            Route.Scoped("https://management-api.x.ai/auth/management-keys/validation", BalanceDecoding::xAITeamID) { team ->
                Endpoint("https://management-api.x.ai/v1/billing/teams/${PathSegment.encode(team)}/prepaid/balance", "USD")
            }) { body, _ -> BalanceDecoding.xAI(body) }

        /// In the order Settings lists them.
        val all = listOf(DEEPSEEK, MOONSHOT, XAI)

        fun descriptor(id: String) = all.firstOrNull { it.id == id }
    }
}

/// A prepaid API balance read with the user's own key, through the provider's official API. Mirrors the Swift
/// `BalanceProvider`: 401/403 → `Unauthenticated`, 429 → `RateLimited` (remembered), anything else → `Server`.
class BalanceClient(
    val descriptor: BalanceDescriptor,
    private val transport: HttpTransport,
    private val tokens: AccessTokenSource,
    private val clock: () -> Instant = Instant::now,
    private val gate: BackoffGate = BackoffGate(),
) {
    private val memo = RouteMemo()

    suspend fun fetch(): UsageInfo {
        val now = clock()
        gate.check(now)?.let { throw UsageError.RateLimited(it) }
        val token = tokens.credentials().token
        val (body, currency) = readBalance(token, now)
        return UsageInfo(descriptor.id, descriptor.name, emptyList(), null, now, descriptor.decode(body, currency))
    }

    private suspend fun readBalance(token: String, now: Instant): Pair<String, String?> = when (val route = descriptor.route) {
        is BalanceDescriptor.Route.Alternatives -> {
            val first = memo.endpoint(token) ?: 0
            val order = listOf(first) + route.endpoints.indices.filter { it != first }
            var result: Pair<String, String?>? = null
            for ((attempt, index) in order.withIndex()) {
                val response = get(route.endpoints[index].url, token)
                val rejected = response.status == 401 || response.status == 403
                if (rejected && attempt < order.size - 1) continue   // maybe a key of the other region
                check(response, now)
                memo.rememberEndpoint(index, token)
                result = response.body to route.endpoints[index].currency
                break
            }
            result ?: throw UsageError.Unauthenticated
        }
        is BalanceDescriptor.Route.Scoped -> {
            val scope = memo.scope(token) ?: run {
                val response = get(route.lookup, token)
                check(response, now)
                val found = route.scopeID(response.body) ?: throw UsageError.Decoding
                memo.rememberScope(found, token)
                found
            }
            val endpoint = route.balance(scope)
            val response = get(endpoint.url, token)
            if (response.status == 401 || response.status == 403) memo.forget(token)
            check(response, now)
            response.body to endpoint.currency
        }
    }

    private fun check(response: HttpResponse, now: Instant) {
        when (response.status) {
            200 -> return
            401, 403 -> throw UsageError.Unauthenticated
            429 -> {
                val until = RetryAfter.until(response.headers, now)
                gate.block(until)
                throw UsageError.RateLimited(until)
            }
            else -> throw UsageError.Server(response.status)
        }
    }

    private suspend fun get(url: String, token: String): HttpResponse =
        sendBearer(transport, url, token, mapOf("Accept" to "application/json"))

    companion object {
        /// Checks a pasted key with one reading before it is saved. Throws `Unauthenticated` for a rejected key.
        suspend fun validate(descriptor: BalanceDescriptor, key: String, transport: HttpTransport): UsageInfo =
            BalanceClient(descriptor, transport, FixedKey(key)).fetch()
    }
}

internal suspend fun sendBearer(transport: HttpTransport, url: String, token: String, headers: Map<String, String>): HttpResponse =
    try {
        transport.send(HttpRequest(url, mapOf("Authorization" to "Bearer $token", "User-Agent" to "AImana") + headers))
    } catch (e: UsageError) {
        throw e
    } catch (e: IOException) {
        throw UsageError.Network
    }

/// Which region host or team a key belongs to. Keyed by the key itself, so saving a different key starts over.
private class RouteMemo {
    private var key: String? = null
    private var endpointIndex: Int? = null
    private var scopeID: String? = null

    @Synchronized fun endpoint(token: String) = if (token == key) endpointIndex else null
    @Synchronized fun scope(token: String) = if (token == key) scopeID else null
    @Synchronized fun rememberEndpoint(index: Int, token: String) {
        if (token != key) { key = token; scopeID = null }
        endpointIndex = index
    }
    @Synchronized fun rememberScope(scope: String, token: String) {
        if (token != key) { key = token; endpointIndex = null }
        scopeID = scope
    }
    @Synchronized fun forget(token: String) {
        if (token == key) { key = null; endpointIndex = null; scopeID = null }
    }
}

/// Like Swift's `urlPathAllowed` minus "/": one path segment, UTF-8 percent-encoded.
internal object PathSegment {
    private const val ALLOWED = "-._~!$&'()*+,;=:@"
    fun encode(text: String): String = buildString {
        for (byte in text.toByteArray(Charsets.UTF_8)) {
            val c = (byte.toInt() and 0xFF).toChar()
            if (c.isLetterOrDigit() && c.code < 128 || c in ALLOWED) append(c) else append("%%%02X".format(byte.toInt() and 0xFF))
        }
    }
}

// MARK: Decoding (pure; parity with BalanceDecoding via AImana/Fixtures/parity/balances)

internal fun parseObject(body: String): JsonObject =
    runCatching { Json.parseToJsonElement(body) as JsonObject }.getOrNull() ?: throw UsageError.Decoding

/// Present and not null, like a decoded Swift optional.
internal fun JsonObject.has(key: String) = this[key].let { it != null && it !is JsonNull }

object BalanceDecoding {
    /// An amount sent as a JSON string (`"110.00"`) or number. Non-finite or unparsable values are null.
    internal fun amount(element: JsonElement?): Double? {
        val p = element as? JsonPrimitive ?: return null
        if (p is JsonNull) return null
        val value = if (p.isString) p.content.trim().toDoubleOrNull() else p.content.toDoubleOrNull()
        return value?.takeIf { it.isFinite() }
    }

    private fun currencyCode(raw: String?): String? =
        raw?.trim()?.uppercase()?.takeIf { code -> code.length == 3 && code.all { it.isLetter() } }

    /// One balance per currency. `is_available: false` (balance too low for API calls) marks each as not usable.
    fun deepSeek(body: String): List<UsageDetail> {
        val root = parseObject(body)
        if (!root.has("is_available") && !root.has("balance_infos")) throw UsageError.Decoding
        val infos = root["balance_infos"]?.takeIf { it !is JsonNull }?.let { it as? JsonArray ?: throw UsageError.Decoding }.orEmpty()
        val blocked = (root["is_available"] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull == false
        return infos.mapNotNull { raw ->
            val info = raw as? JsonObject ?: return@mapNotNull null
            if (info.has("currency") && (info["currency"] as? JsonPrimitive)?.isString != true) return@mapNotNull null
            val currency = currencyCode(info.str("currency")) ?: return@mapNotNull null
            val total = amount(info["total_balance"]) ?: return@mapNotNull null
            UsageDetail("creditBalance", total, currency = currency, usable = if (blocked || total <= 0) 0.0 else null)
        }
    }

    /// `available_balance` (cash plus vouchers); API calls stop at zero or below.
    fun moonshot(body: String, currency: String): List<UsageDetail> {
        val available = amount(parseObject(body).obj("data")?.get("available_balance")) ?: throw UsageError.Decoding
        return listOf(UsageDetail("creditBalance", available, currency = currency, usable = if (available <= 0) 0.0 else null))
    }

    fun xAITeamID(body: String): String? =
        runCatching { parseObject(body) }.getOrNull()?.str("teamId")?.trim()?.takeIf { it.isNotEmpty() }

    /// `total.val` is USD cents with purchases negative, so the spendable balance is its negation.
    fun xAI(body: String): List<UsageDetail> {
        val cents = amount(parseObject(body).obj("total")?.get("val")) ?: throw UsageError.Decoding
        val dollars = -cents / 100
        return listOf(UsageDetail("creditBalance", if (dollars == 0.0) 0.0 else dollars, currency = "USD",
                                  usable = if (dollars <= 0) 0.0 else null))
    }
}
