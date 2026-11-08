package com.henrrygarcia.aimana.desktop.relay

import com.henrrygarcia.aimana.core.RelayCodec
import com.henrrygarcia.aimana.core.RelayEnvelope
import com.henrrygarcia.aimana.desktop.cli.CliPaths
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/// Runs the published `usage-relay` binary for the local sources (Claude statusline, Codex logs, costs) and reads the
/// file it writes. The app never reimplements those readers and never rewrites the relay file itself.
class RelayWorker(
    private val binary: Path?,
    private val output: Path,
    /// `usage-relay setup`'s record: when present, publish where it says (the folder synced with the phone).
    private val setupRecord: Path? = null,
    private val run: (List<String>) -> Int = ::defaultRun,
) {
    /// Why the last publish failed (missing binary, non-zero exit, unreadable file), or null.
    @Volatile var lastError: String? = null
        private set

    /// The synced file `usage-relay setup` recorded, if it ran.
    val setupOutput: Path? get() = setupRecord?.takeIf { Files.isRegularFile(it) }?.let(::recordedOutput)

    /// The file the last publish wrote: the synced folder's when set up, otherwise the local one.
    val publishedFile: Path get() = setupRecord?.let(::recordedOutput) ?: output

    suspend fun publishOnce(): RelayEnvelope? = withContext(Dispatchers.IO) {
        val record = setupRecord?.takeIf { Files.isRegularFile(it) && recordedOutput(it) != null }
        val arguments = if (record != null) listOf("run", "--config", record.toString()) else listOf("run", "--output", output.toString())
        lastError = when {
            binary == null -> "usage-relay not found"
            else -> runCatching { run(listOf(binary.toString()) + arguments) }
                .fold({ code -> if (code != 0) "usage-relay exited with status $code" else null },
                      { "usage-relay could not start" })
        }
        // A failed run still leaves the last good file in place: show it rather than nothing.
        readLast()
    }

    /// The last published file, without running anything (the panel reads what the tray published).
    suspend fun readLast(): RelayEnvelope? = withContext(Dispatchers.IO) {
        val text = runCatching { Files.readString(publishedFile) }.getOrNull()
        text?.let { runCatching { RelayCodec.decode(it) }.onFailure { lastError = "relay file unreadable" }.getOrNull() }
    }

    companion object {
        /// `output` of a setup record, a file URL as Swift encodes it.
        private fun recordedOutput(record: Path): Path? = runCatching {
            val json = kotlinx.serialization.json.Json.parseToJsonElement(Files.readString(record)) as kotlinx.serialization.json.JsonObject
            val value = (json["output"] as kotlinx.serialization.json.JsonPrimitive).content
            if (value.startsWith("file:")) Path.of(java.net.URI(value)) else Path.of(value)
        }.getOrNull()

        /// Next to the app or one folder up (the installer puts the tray app in `{app}\app`), in the relay's own
        /// folder, or in `~/.local/bin`. Never through PATH.
        fun locate(paths: CliPaths, appDir: Path?): Path? {
            val name = if (paths.isWindows) "usage-relay.exe" else "usage-relay"
            val candidates = listOfNotNull(appDir?.resolve(name), appDir?.parent?.resolve(name), paths.stateDir.resolve(name),
                                           paths.home.resolve(".local/bin").resolve(name))
            return candidates.firstOrNull { Files.isRegularFile(it) }
        }

        private fun defaultRun(command: List<String>): Int {
            val process = ProcessBuilder(command).redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD).start()
            if (!process.waitFor(120, TimeUnit.SECONDS)) { process.destroyForcibly(); return -1 }
            return process.exitValue()
        }
    }
}
