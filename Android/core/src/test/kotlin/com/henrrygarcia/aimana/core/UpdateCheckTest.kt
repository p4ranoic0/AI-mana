package com.henrrygarcia.aimana.core

import com.henrrygarcia.aimana.core.net.HttpTransport
import com.henrrygarcia.aimana.core.providers.MockTransport
import com.henrrygarcia.aimana.core.providers.reply
import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.io.IOException
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateCheckTest {
    private var now = Instant.parse("2027-01-15T08:00:00Z")
    private val store = InMemoryKeyValueStore()
    private fun release(tag: String) = reply(200, """{"tag_name":"$tag","html_url":"https://example.com/elsewhere","draft":false}""")
    private fun check(transport: HttpTransport, current: String = "1.2.0") = UpdateCheck(transport, current, store) { now }

    @Test fun newerReleaseIsReported() = runBlocking {
        val transport = MockTransport(mutableListOf(release("v1.3.0")))
        val update = check(transport).refresh()
        assertEquals(AppUpdate("1.3.0"), update)
        // The link is built from the version, never taken from the response.
        assertEquals("https://github.com/p4ranoic0/AI-mana/releases/tag/v1.3.0", update?.pageUrl)
        assertEquals(listOf(UpdateCheck.LATEST_URL), transport.requests.map { it.url })
    }

    @Test fun sameOrOlderReleaseIsNotAnUpdate() = runBlocking {
        assertNull(check(MockTransport(mutableListOf(release("v1.2.0")))).refresh())
        assertNull(check(MockTransport(mutableListOf(release("v1.1.9")))).refresh())
    }

    @Test fun versionsCompareNumerically() {
        assertTrue(UpdateCheck.versionCode("v1.10.0")!! > UpdateCheck.versionCode("1.9.9")!!)
        assertEquals(10203, UpdateCheck.versionCode("1.2.3"))
        assertNull(UpdateCheck.versionCode("1.3.0-beta"))
        assertNull(UpdateCheck.versionCode("1.100.0"))
        assertNull(UpdateCheck.versionCode("latest"))
    }

    @Test fun asksAtMostOncePerDay() = runBlocking {
        val transport = MockTransport(mutableListOf(release("v1.3.0"), release("v1.4.0")))
        val check = check(transport)
        check.refresh()
        now = now.plus(Duration.ofHours(23))
        assertEquals(AppUpdate("1.3.0"), check.refresh())   // remembered, no request
        assertEquals(1, transport.requests.size)
        now = now.plus(Duration.ofHours(2))
        assertEquals(AppUpdate("1.4.0"), check.refresh())
        assertEquals(2, transport.requests.size)
    }

    @Test fun failuresAreSilentAndKeepTheLastAnswer() = runBlocking {
        check(MockTransport(mutableListOf(release("v1.3.0")))).refresh()
        now = now.plus(Duration.ofDays(2))
        assertEquals(AppUpdate("1.3.0"), check(HttpTransport { throw IOException("offline") }).refresh())
        now = now.plus(Duration.ofDays(2))
        assertEquals(AppUpdate("1.3.0"), check(MockTransport(mutableListOf(reply(500)))).refresh())
        now = now.plus(Duration.ofDays(2))
        assertEquals(AppUpdate("1.3.0"), check(MockTransport(mutableListOf(reply(200, "not json")))).refresh())
    }

    @Test fun installingTheUpdateClearsIt() = runBlocking {
        check(MockTransport(mutableListOf(release("v1.3.0")))).refresh()
        assertEquals(AppUpdate("1.3.0"), check(MockTransport(mutableListOf())).available())
        assertNull(check(MockTransport(mutableListOf()), current = "1.3.0").available())
    }

    @Test fun turnedOffMakesNoRequest() = runBlocking {
        val transport = MockTransport(mutableListOf(release("v1.3.0")))
        val check = check(transport)
        check.enabled = false
        assertNull(check.refresh())
        assertEquals(0, transport.requests.size)
        check.enabled = true
        assertEquals(AppUpdate("1.3.0"), check.refresh())
    }
}
