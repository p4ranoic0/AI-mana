package com.henrrygarcia.aimana.desktop.cli

import com.henrrygarcia.aimana.core.providers.AccessCredential
import com.henrrygarcia.aimana.core.providers.AccessTokenSource
import com.henrrygarcia.aimana.core.providers.UsageError
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/// Same rule as the Swift `RenewalPolicy`: renew within 120 s of expiry, at most once every 20 minutes.
object RenewalPolicy {
    val expirySkew: Duration = Duration.ofSeconds(120)
    val cooldown: Duration = Duration.ofMinutes(20)

    fun shouldAttempt(expiresAt: Instant?, lastAttempt: Instant?, now: Instant): Boolean {
        expiresAt ?: return false
        if (Duration.between(now, expiresAt) > expirySkew) return false
        if (lastAttempt != null && !lastAttempt.isAfter(now) && Duration.between(lastAttempt, now) < cooldown) return false
        return true
    }
}

/// Asks the Claude CLI to renew its own session. The CLI owns the credential and rewrites its file; AI·mana never
/// reads, copies or writes a refresh token, and only observes whether the expiry moved. `claude auth status` makes no
/// model call. Its output contains the account email, so it is discarded.
class ClaudeRenewer(
    private val paths: CliPaths,
    private val read: () -> ClaudeCredentialsFile.OAuth?,
    private val log: (String) -> Unit = {},
) {
    sealed class Outcome { data object Renewed : Outcome(); data object Unchanged : Outcome(); data class Failed(val reason: String) : Outcome() }

    private val stateFile: Path get() = paths.stateDir.resolve("claude-renew.json")

    fun lastAttempt(): Instant? = runCatching {
        Instant.ofEpochSecond(Files.readString(stateFile).filter { it.isDigit() }.toLong())
    }.getOrNull()

    private fun recordAttempt(now: Instant) {
        runCatching {
            Files.createDirectories(stateFile.parent)
            Files.writeString(stateFile, """{"lastAttempt":${now.epochSecond}}""")
        }
    }

    /// Never resolved through PATH: a shell shim may sit first there.
    fun binary(): Path? {
        val home = paths.home
        val candidates = buildList {
            paths.env["CLAUDE_BIN"]?.takeIf { it.isNotBlank() }?.let { add(Path.of(it)) }
            if (paths.isWindows) {
                add(home.resolve(".local/bin/claude.exe"))
                paths.env["LOCALAPPDATA"]?.let { add(Path.of(it, "Microsoft", "WinGet", "Links", "claude.exe")) }
            } else {
                add(home.resolve(".local/bin/claude"))
                add(Path.of("/usr/local/bin/claude"))
            }
        }
        return candidates.firstOrNull { Files.isRegularFile(it) && Files.isExecutable(it) }
    }

    suspend fun attempt(now: Instant = Instant.now(), timeout: Duration = Duration.ofSeconds(30)): Outcome {
        val binary = binary() ?: return Outcome.Failed("claude CLI not found")
        recordAttempt(now)
        val before = read()?.expiresAt
        val exit = withContext(Dispatchers.IO) {
            val process = runCatching {
                ProcessBuilder(binary.toString(), "auth", "status", "--json")
                    .redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD)
                    .redirectInput(ProcessBuilder.Redirect.from(if (paths.isWindows) Path.of("NUL").toFile() else Path.of("/dev/null").toFile()))
                    .start()
            }.getOrNull() ?: return@withContext null
            if (!process.waitFor(timeout.seconds, TimeUnit.SECONDS)) { process.destroyForcibly(); -1 } else process.exitValue()
        }
        val outcome = when {
            exit == null -> Outcome.Failed("could not start CLI")
            exit == -1 -> Outcome.Failed("CLI timed out after ${timeout.seconds}s")
            exit != 0 -> Outcome.Failed("CLI exited with status $exit")
            else -> {
                // The CLI may write its file slightly after it exits.
                var result: Outcome = Outcome.Unchanged
                repeat(20) {
                    val after = read()?.expiresAt
                    if (after != null && after.isAfter(before ?: Instant.MIN)) { result = Outcome.Renewed; return@repeat }
                    delay(400)
                }
                result
            }
        }
        log("claude: renewal $outcome")
        return outcome
    }
}

/// Claude Code's session file, renewed through the CLI when it is about to expire and `renew` is on.
class ClaudeCliTokens(
    private val renew: Boolean,
    private val paths: CliPaths,
    private val file: ClaudeCredentialsFile = ClaudeCredentialsFile(paths),
    private val renewer: ClaudeRenewer = ClaudeRenewer(paths, file::readOAuth),
) : AccessTokenSource {
    override suspend fun credentials(): AccessCredential {
        val oauth = file.readOAuth() ?: throw UsageError.Unauthenticated
        if (renew && RenewalPolicy.shouldAttempt(oauth.expiresAt, renewer.lastAttempt(), Instant.now())) renewer.attempt()
        return file.credentials()
    }
}
