package com.henrrygarcia.aimana.core.net

data class HttpRequest(val url: String, val headers: Map<String, String>, val method: String = "GET", val body: String? = null) {
    /// Headers and body carry tokens, refresh tokens and PKCE verifiers: never printed.
    override fun toString() = "HttpRequest($method $url, headers=${headers.keys}, body=${body?.let { "<${it.length} chars>" }})"
}

data class HttpResponse(val status: Int, val headers: Map<String, String>, val body: String) {
    /// Header names are case-insensitive.
    fun header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
    override fun toString() = "HttpResponse($status, headers=${headers.keys}, body=<${body.length} chars>)"
}

/// The only network contract of the core: each host (desktop, Android) supplies its implementation. Transport failures
/// throw `java.io.IOException`, which clients report as a network error.
fun interface HttpTransport {
    suspend fun send(request: HttpRequest): HttpResponse
}
