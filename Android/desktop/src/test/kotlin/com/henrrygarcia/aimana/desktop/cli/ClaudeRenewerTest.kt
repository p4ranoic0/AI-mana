package com.henrrygarcia.aimana.desktop.cli

import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.Collections
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClaudeRenewerTest {
    private val windows = System.getProperty("os.name").startsWith("Windows")
    private val home: Path = Files.createTempDirectory("aimana-renew-test")
    private val credentials: Path = home.resolve(".claude/.credentials.json")
    private val marker: Path = home.resolve("cli-ran")
    private val renewed = """{"claudeAiOauth":{"accessToken":"renewed","expiresAt":4102444800000,"subscriptionType":"max"}}"""

    /// A fake `claude` that prints an email (must be discarded) and rewrites its own session, like Claude Code does.
    private fun fakeClaude(): Path {
        Files.createDirectories(credentials.parent)
        return if (windows) {
            home.resolve("claude.cmd").also {
                Files.writeString(it, "@echo off\r\necho someone@example.com\r\ntype nul > \"$marker\"\r\n" +
                    "echo $renewed> \"$credentials\"\r\n")
            }
        } else {
            home.resolve("claude").also {
                Files.writeString(it, "#!/bin/sh\necho someone@example.com\ntouch '$marker'\nprintf '%s' '$renewed' > '$credentials'\n")
                it.toFile().setExecutable(true)
            }
        }
    }

    private fun expired() = Files.writeString(credentials.also { Files.createDirectories(it.parent) },
        """{"claudeAiOauth":{"accessToken":"old","expiresAt":${Instant.now().minusSeconds(60).toEpochMilli()}}}""")

    @Test fun renewalRunsTheClaudeCLIAndPicksUpTheNewSession() = runBlocking {
        val bin = fakeClaude()
        expired()
        val paths = CliPaths(home, mapOf("CLAUDE_BIN" to bin.toString()), windows)
        val credential = ClaudeCliTokens(renew = true, paths = paths).credentials()
        assertTrue(Files.exists(marker))
        assertEquals("renewed", credential.token)
    }

    @Test fun cooldownPreventsASecondAttempt() = runBlocking {
        val bin = fakeClaude()
        expired()
        val paths = CliPaths(home, mapOf("CLAUDE_BIN" to bin.toString()), windows)
        val renewer = ClaudeRenewer(paths, ClaudeCredentialsFile(paths)::readOAuth)
        renewer.attempt(Instant.now())
        Files.delete(marker)
        assertFalse(RenewalPolicy.shouldAttempt(Instant.now(), renewer.lastAttempt(), Instant.now()))
    }

    @Test fun stdoutIsDiscarded() = runBlocking {
        val bin = fakeClaude()
        expired()
        val logs = Collections.synchronizedList(mutableListOf<String>())
        val paths = CliPaths(home, mapOf("CLAUDE_BIN" to bin.toString()), windows)
        ClaudeRenewer(paths, ClaudeCredentialsFile(paths)::readOAuth, log = { logs += it }).attempt(Instant.now())
        assertTrue(logs.none { it.contains("example.com") })
    }

    @Test fun neverResolvesThroughPath() {
        val bin = fakeClaude()
        val paths = CliPaths(home, mapOf("PATH" to bin.parent.toString()), windows)
        assertNull(ClaudeRenewer(paths, { null }).binary())
    }

    @Test fun policyMatchesSwift() {
        val now = Instant.parse("2027-01-10T00:00:00Z")
        assertTrue(RenewalPolicy.shouldAttempt(now.plusSeconds(100), null, now))
        assertFalse(RenewalPolicy.shouldAttempt(now.plusSeconds(600), null, now))
        assertFalse(RenewalPolicy.shouldAttempt(now.minusSeconds(1), now.minusSeconds(60), now))
        assertTrue(RenewalPolicy.shouldAttempt(now.minusSeconds(1), now.minusSeconds(21 * 60), now))
        assertFalse(RenewalPolicy.shouldAttempt(null, null, now))
    }
}
