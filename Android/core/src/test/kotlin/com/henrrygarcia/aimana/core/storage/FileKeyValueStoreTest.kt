package com.henrrygarcia.aimana.core.storage

import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assume.assumeFalse
import org.junit.Test

class FileKeyValueStoreTest {
    private val dir = Files.createTempDirectory("aimana-prefs-test")
    private val file = dir.resolve("desktop-preferences.json")

    @Test fun roundTrip() {
        val store = FileKeyValueStore(file)
        store.putDouble("directAccess.claude.consentedAt", 1_700_000_000.5)
        store.putInt("directAccess.claude.noticeVersion", 1)
        val reloaded = FileKeyValueStore(file)
        assertEquals(1_700_000_000.5, reloaded.getDouble("directAccess.claude.consentedAt")!!, 0.0)
        assertEquals(1, reloaded.getInt("directAccess.claude.noticeVersion"))
        reloaded.remove("directAccess.claude.noticeVersion")
        assertNull(FileKeyValueStore(file).getInt("directAccess.claude.noticeVersion"))
    }

    @Test fun atomicWriteSurvivesCrashMidWrite() {
        FileKeyValueStore(file).putInt("a", 1)
        // A crash after writing the temporary file but before the rename leaves the old file intact.
        Files.writeString(dir.resolve("desktop-preferences.json.tmp"), "{\"a\": 2, broken")
        assertEquals(1, FileKeyValueStore(file).getInt("a"))
    }

    @Test fun twoProcessesNeverLoseEachOthersWrites() {
        // Two instances stand for the panel and a `--check` run writing the same file at once.
        val a = FileKeyValueStore(file)
        val b = FileKeyValueStore(file)
        val threads = listOf(Thread { repeat(100) { a.putInt("backoff.claude.until", it) } },
                             Thread { repeat(100) { b.putInt("directAccess.codex.noticeVersion", it) } })
        threads.forEach(Thread::start)
        threads.forEach(Thread::join)
        val reloaded = FileKeyValueStore(file)
        assertEquals(99, reloaded.getInt("backoff.claude.until"))
        assertEquals(99, reloaded.getInt("directAccess.codex.noticeVersion"))
    }

    @Test fun corruptFileReadsAsEmpty() {
        Files.writeString(file, "not json")
        assertNull(FileKeyValueStore(file).getInt("a"))
    }

    @Test fun unixPermissionsAre0600() {
        assumeFalse(System.getProperty("os.name").startsWith("Windows"))
        FileKeyValueStore(file).putInt("a", 1)
        assertEquals("rw-------", PosixFilePermissions.toString(Files.getPosixFilePermissions(file)))
    }
}
