package com.henrrygarcia.aimana.desktop.net

import com.henrrygarcia.aimana.core.net.HttpRequest
import com.henrrygarcia.aimana.core.net.HttpResponse
import com.henrrygarcia.aimana.core.net.HttpTransport
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpResponse.BodyHandlers
import java.time.Duration
import kotlinx.coroutines.future.await

/// `java.net.http` for the desktop app (Android uses its own transport).
class JdkHttpTransport(private val timeout: Duration = Duration.ofSeconds(15)) : HttpTransport {
    private val client: HttpClient = HttpClient.newBuilder().connectTimeout(timeout).build()

    override suspend fun send(request: HttpRequest): HttpResponse {
        val publisher = request.body?.let { java.net.http.HttpRequest.BodyPublishers.ofString(it) }
            ?: java.net.http.HttpRequest.BodyPublishers.noBody()
        val builder = java.net.http.HttpRequest.newBuilder(URI(request.url)).timeout(timeout).method(request.method, publisher)
        request.headers.forEach { (name, value) -> builder.header(name, value) }
        val response = client.sendAsync(builder.build(), BodyHandlers.ofString()).await()
        return HttpResponse(response.statusCode(), response.headers().map().mapValues { it.value.joinToString(",") }, response.body())
    }
}
