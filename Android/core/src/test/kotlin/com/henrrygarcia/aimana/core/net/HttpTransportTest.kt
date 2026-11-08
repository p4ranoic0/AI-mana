package com.henrrygarcia.aimana.core.net

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HttpTransportTest {
    @Test fun requestsAndResponsesNeverPrintSecrets() {
        val secret = "SENTINEL-SECRET-123"
        val request = HttpRequest("https://example.com/token", mapOf("Authorization" to "Bearer $secret"), "POST", "refresh_token=$secret")
        val response = HttpResponse(200, mapOf("Set-Cookie" to secret), """{"access_token":"$secret"}""")
        for (text in listOf(request.toString(), response.toString())) assertFalse(text, secret in text)
        assertTrue(request.toString().contains("https://example.com/token"))
        assertTrue(response.toString().contains("200"))
    }
}
