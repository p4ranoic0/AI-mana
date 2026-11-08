package com.henrrygarcia.aimana.desktop.relay

import com.henrrygarcia.aimana.core.DirectAccessConsent
import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.core.UsageInfo
import com.henrrygarcia.aimana.core.UsageWindow
import com.henrrygarcia.aimana.core.providers.UsageError
import com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopUsageTest {
    private val dir: Path = Files.createTempDirectory("aimana-desktop-usage")
    private val output: Path = dir.resolve("usage-relay.json")
    private val t = Instant.parse("2027-01-10T00:00:00Z")
    private val envelope = """{"version":1,"generatedAt":"2027-01-10T00:00:00Z","entries":[
        {"providerID":"claude","source":"statusline","usage":{"providerID":"claude","providerName":"Claude Code","windows":[{"kind":"session","usedPercent":42,"windowMinutes":300}],"lastUpdated":"2027-01-10T00:00:00Z"}},
        {"providerID":"codex","source":"logs","usage":{"providerID":"codex","providerName":"OpenAI Codex","windows":[{"kind":"weekly","usedPercent":7,"windowMinutes":10080}],"lastUpdated":"2027-01-10T00:00:00Z"}}]}"""
    private fun direct(id: String, used: Double) = UsageInfo(id, id, listOf(UsageWindow("session", used, 300)), null, t)

    /// Writes the envelope where the real CLI would, and counts runs.
    private fun worker(runs: AtomicInteger = AtomicInteger(), exit: Int = 0, binary: Path? = dir.resolve("usage-relay")) =
        RelayWorker(binary, output, run = { args -> runs.incrementAndGet(); assertEquals(listOf("run", "--output", output.toString()), args.drop(1)); Files.writeString(output, envelope); exit })

    private fun sha(path: Path) = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(path)).joinToString("") { "%02x".format(it) }

    @Test fun workerOutputIsDecoded() = runBlocking {
        val env = worker().publishOnce()!!
        assertEquals(42.0, env.provider("claude").first!!.primary!!.usedPercent, 0.0)
    }

    @Test fun missingBinaryReportsAndDirectStillWorks() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore()).also { it.grant(DirectProvider.CLAUDE) }
        val usage = DesktopUsage(worker(binary = null), consent, claude = { direct("claude", 10.0) }, codex = { direct("codex", 3.0) })
        val states = usage.refresh().associateBy { it.providerID }
        assertEquals(10.0, states["claude"]!!.usage!!.primary!!.usedPercent, 0.0)
        assertNull(states["claude"]!!.error)
        assertNull(states["codex"]!!.usage)                  // no relay, no consent: nothing, never 0 %
        assertEquals(UsageError.RelayUnavailable, states["codex"]!!.error)
        assertTrue(usage.relayProblem != null)
    }

    @Test fun directIsGatedByConsentEveryRefresh() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore())
        val calls = AtomicInteger()
        val usage = DesktopUsage(worker(), consent, claude = { calls.incrementAndGet(); direct("claude", 10.0) }, codex = { direct("codex", 3.0) })
        assertEquals(42.0, usage.refresh().first { it.providerID == "claude" }.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(0, calls.get())
        consent.grant(DirectProvider.CLAUDE)
        assertEquals(10.0, usage.refresh().first { it.providerID == "claude" }.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(1, calls.get())
    }

    @Test fun revokedDuringRefreshPublishesNoDirectReading() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore()).also { it.grant(DirectProvider.CLAUDE) }
        val usage = DesktopUsage(worker(), consent, claude = { consent.revoke(DirectProvider.CLAUDE); direct("claude", 10.0) },
                                 codex = { direct("codex", 3.0) })
        assertEquals(42.0, usage.refresh().first { it.providerID == "claude" }.usage!!.primary!!.usedPercent, 0.0)
    }

    @Test fun relayFileIsNeverRewritten() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore()).also { it.grant(DirectProvider.CLAUDE); it.grant(DirectProvider.CODEX) }
        val usage = DesktopUsage(worker(), consent, claude = { direct("claude", 10.0) }, codex = { direct("codex", 3.0) })
        usage.refresh()
        val before = sha(output)
        usage.refresh()   // the worker rewrites the same envelope; the merge itself never touches the file
        assertEquals(before, sha(output))
    }

    @Test fun locateFindsTheRelayNextToTheInstalledApp() {
        // Installed layout: {app}\usage-relay.exe and the tray app in {app}\app\AImana.exe.
        val installed = dir.resolve("install")
        val appDir = Files.createDirectories(installed.resolve("app"))
        val relay = Files.writeString(installed.resolve("usage-relay.exe"), "")
        val paths = com.henrrygarcia.aimana.desktop.cli.CliPaths(dir.resolve("home"), emptyMap(), isWindows = true)
        assertEquals(relay, RelayWorker.locate(paths, appDir))
    }

    @Test fun setupRecordPublishesToTheSyncedFolder() = runBlocking {
        // `usage-relay setup` recorded the folder the user chose; the worker publishes there, for the phone too.
        val synced = Files.createDirectories(dir.resolve("OneDrive/AImana")).resolve("usage-relay.json")
        val record = Files.writeString(dir.resolve("setup.json"), """{"output":"${synced.toUri()}","interval":5,"statuslineInstalled":true,"schedulerInstalled":false}""")
        val seen = mutableListOf<List<String>>()
        val worker = RelayWorker(dir.resolve("usage-relay"), output, setupRecord = record, run = { args -> seen += args; Files.writeString(synced, envelope); 0 })
        val env = worker.publishOnce()!!
        assertEquals(listOf("run", "--config", record.toString()), seen.single().drop(1))
        assertEquals(42.0, env.provider("claude").first!!.primary!!.usedPercent, 0.0)
        assertEquals(synced, worker.publishedFile)
    }

    @Test fun revokingClaudeWhileCodexIsPendingDropsClaudesDirectReading() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore()).also { it.grant(DirectProvider.CLAUDE); it.grant(DirectProvider.CODEX) }
        val usage = DesktopUsage(worker(), consent, claude = { direct("claude", 10.0) },
                                 codex = { consent.revoke(DirectProvider.CLAUDE); direct("codex", 3.0) })
        val claude = usage.refresh().first { it.providerID == "claude" }
        assertEquals(42.0, claude.usage!!.primary!!.usedPercent, 0.0)   // the relay's, not the revoked direct 10 %
    }

    @Test fun relayThatCannotStartDoesNotStopDirectAccess() = runBlocking {
        val consent = DirectAccessConsent(InMemoryKeyValueStore()).also { it.grant(DirectProvider.CLAUDE) }
        val broken = RelayWorker(dir.resolve("usage-relay"), output, run = { throw java.io.IOException("access denied") })
        val usage = DesktopUsage(broken, consent, claude = { direct("claude", 10.0) }, codex = { direct("codex", 3.0) })
        assertEquals(10.0, usage.refresh().first { it.providerID == "claude" }.usage!!.primary!!.usedPercent, 0.0)
        assertTrue(usage.relayProblem!!.contains("could not start"))
    }

    @Test fun panelOnlyReadsWhatTheTrayPublished() = runBlocking {
        val runs = AtomicInteger()
        Files.writeString(output, envelope)
        val consent = DirectAccessConsent(InMemoryKeyValueStore())
        val usage = DesktopUsage(worker(runs), consent, claude = { direct("claude", 10.0) }, codex = { direct("codex", 3.0) },
                                 publish = false)
        assertEquals(42.0, usage.refresh().first { it.providerID == "claude" }.usage!!.primary!!.usedPercent, 0.0)
        assertEquals(0, runs.get())
    }

    @Test fun failingWorkerKeepsLastEnvelope() = runBlocking {
        val runs = AtomicInteger()
        val good = worker(runs)
        good.publishOnce()
        val broken = RelayWorker(dir.resolve("usage-relay"), output, run = { 1 })
        assertEquals(42.0, broken.publishOnce()!!.provider("claude").first!!.primary!!.usedPercent, 0.0)
        assertTrue(broken.lastError != null)
    }
}
