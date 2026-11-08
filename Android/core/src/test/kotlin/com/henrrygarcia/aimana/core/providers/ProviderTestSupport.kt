package com.henrrygarcia.aimana.core.providers

import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import java.io.File
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals

class MockTransport(private val replies: MutableList<HttpResponse>) : HttpTransport {
    val requests = mutableListOf<HttpRequest>()
    override suspend fun send(request: HttpRequest): HttpResponse {
        synchronized(this) { requests += request }
        return synchronized(this) { if (replies.isEmpty()) HttpResponse(500, emptyMap(), "") else replies.removeAt(0) }
    }
}

fun reply(status: Int, body: String = "", headers: Map<String, String> = emptyMap()) = HttpResponse(status, headers, body)

class FixedTokens(private val credential: AccessCredential = AccessCredential("tok", "acct")) : AccessTokenSource {
    override suspend fun credentials() = credential
}

/// The shared fixtures under AImana/Fixtures/parity, which the Swift tests read too.
fun parityFixture(name: String): JsonObject =
    Json.parseToJsonElement(File("../../AImana/Fixtures/parity/$name").readText()).jsonObject

fun assertMatchesExpected(usage: UsageInfo, expected: JsonObject) {
    val windows = expected["windows"]!!.jsonArray.map { it.jsonObject }
    assertEquals(windows.map { it["kind"]!!.jsonPrimitive.content }, usage.windows.map { it.kind })
    usage.windows.zip(windows).forEach { (window, want) ->
        assertEquals(want["usedPercent"]!!.jsonPrimitive.doubleOrNull!!, window.usedPercent, 1e-9)
        assertEquals(want["windowMinutes"]?.jsonPrimitive?.intOrNull, window.windowMinutes)
        assertEquals(want["resetsAt"]?.jsonPrimitive?.contentOrNull?.let(Instant::parse), window.resetsAt)
    }
    val details = expected["details"]!!.jsonArray.map { it.jsonObject }
    assertEquals(details.map { it["kind"]!!.jsonPrimitive.content }, usage.details.map { it.kind })
    usage.details.zip(details).forEach { (detail, want) ->
        assertEquals(want["remaining"]!!.jsonPrimitive.doubleOrNull!!, detail.remaining, 1e-9)
        assertEquals(want["limit"]?.jsonPrimitive?.doubleOrNull, detail.limit)
        assertEquals(want["currency"]?.jsonPrimitive?.contentOrNull, detail.currency)
        assertEquals(want["used"]?.jsonPrimitive?.doubleOrNull, detail.used)
        assertEquals(want["usable"]?.jsonPrimitive?.doubleOrNull, detail.usable)
        assertEquals(want["expiresAt"]?.jsonPrimitive?.contentOrNull?.let(Instant::parse), detail.expiresAt)
    }
}
