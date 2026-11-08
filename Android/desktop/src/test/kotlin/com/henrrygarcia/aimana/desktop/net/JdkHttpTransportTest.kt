package com.henrrygarcia.aimana.desktop.net

import com.henrrygarcia.aimana.core.net.HttpRequest
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class JdkHttpTransportTest {
    @Test fun jdkTransportSendsPostBody() = runBlocking {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        var seen = ""
        server.createContext("/token") { exchange ->
            seen = exchange.requestMethod + " " + exchange.requestHeaders.getFirst("Content-Type") + " " +
                exchange.requestBody.readBytes().decodeToString()
            val reply = """{"ok":true}""".toByteArray()
            exchange.sendResponseHeaders(200, reply.size.toLong())
            exchange.responseBody.use { it.write(reply) }
        }
        server.start()
        try {
            val response = JdkHttpTransport().send(HttpRequest("http://127.0.0.1:${server.address.port}/token",
                mapOf("Content-Type" to "application/json"), method = "POST", body = """{"a":1}"""))
            assertEquals(200, response.status)
            assertEquals("""POST application/json {"a":1}""", seen)
        } finally {
            server.stop(0)
        }
    }
}
