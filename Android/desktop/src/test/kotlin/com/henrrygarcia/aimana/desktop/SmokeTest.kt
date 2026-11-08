package com.henrrygarcia.aimana.desktop

import java.io.ByteArrayOutputStream
import java.io.PrintStream
import org.junit.Assert.assertTrue
import org.junit.Test

class SmokeTest {
    @Test fun checkReadsAGivenRelayFile() {
        // The CI smoke run of the ProGuard build uses this mode: it must really decode the relay file.
        val lines = kotlinx.coroutines.runBlocking { checkRelayFile(java.nio.file.Path.of("src/test/resources/relay-sample.json")) }
        assertTrue(lines.any { it.startsWith("Claude Code: 42%") })
        assertTrue(lines.any { it.startsWith("OpenAI Codex: 7%") })
    }

    @Test fun versionFlagPrintsVersion() {
        val out = ByteArrayOutputStream()
        val previous = System.out
        System.setOut(PrintStream(out, true, Charsets.UTF_8))
        try { main(arrayOf("--version")) } finally { System.setOut(previous) }
        assertTrue(out.toString(Charsets.UTF_8).startsWith("AImana "))
    }
}
