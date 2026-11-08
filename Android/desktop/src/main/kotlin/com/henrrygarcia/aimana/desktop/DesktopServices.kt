package com.henrrygarcia.aimana.desktop

import com.henrrygarcia.aimana.core.DirectAccessConsent
import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.core.net.BackoffGate
import com.henrrygarcia.aimana.core.providers.ClaudeUsageClient
import com.henrrygarcia.aimana.core.providers.CodexUsageClient
import com.henrrygarcia.aimana.desktop.cli.ClaudeCliTokens
import com.henrrygarcia.aimana.desktop.cli.CliPaths
import com.henrrygarcia.aimana.desktop.cli.CodexAuthFile
import com.henrrygarcia.aimana.desktop.net.JdkHttpTransport
import com.henrrygarcia.aimana.desktop.platform.Autostart
import com.henrrygarcia.aimana.desktop.relay.DesktopUsage
import com.henrrygarcia.aimana.desktop.relay.RelayWorker
import com.henrrygarcia.aimana.core.storage.FileKeyValueStore
import com.henrrygarcia.aimana.core.UpdateCheck
import java.nio.file.Path

/// The composition root: the only place that knows where each piece comes from.
class DesktopServices(
    val paths: CliPaths,
    val store: FileKeyValueStore,
    val consent: DirectAccessConsent,
    val usage: DesktopUsage,
    val worker: RelayWorker,
    val relayBinary: Path?,
    val autostart: Autostart?,
    /// Whether a newer public release is out (asks GitHub at most once a day; can be turned off in Settings).
    val updates: UpdateCheck,
) {
    var intervalMinutes: Int
        get() = store.getInt(INTERVAL_KEY)?.coerceIn(1, 60) ?: 5
        set(value) = store.putInt(INTERVAL_KEY, value.coerceIn(1, 60))

    companion object {
        private const val INTERVAL_KEY = "settings.intervalMinutes"

        /// `publishes`: false for the panel process, which reads what the tray published instead of running usage-relay.
        fun create(publishes: Boolean = true): DesktopServices {
            val paths = CliPaths.current()
            val store = FileKeyValueStore(paths.stateDir.resolve("desktop-preferences.json"))
            val consent = DirectAccessConsent(store)
            val transport = JdkHttpTransport()
            // The CLI sessions are read only when the user's consent holds (DesktopUsage checks it on every fetch).
            val claude = ClaudeUsageClient(transport, ClaudeCliTokens(renew = true, paths = paths),
                                           gate = BackoffGate.shared("claude", store),
                                           isAllowed = { consent.isGranted(DirectProvider.CLAUDE) })
            val codex = CodexUsageClient(transport, CodexAuthFile(paths), gate = BackoffGate.shared("codex", store),
                                         isAllowed = { consent.isGranted(DirectProvider.CODEX) })
            // jpackage sets the launcher path; it is absent when running from Gradle.
            val launcher = System.getProperty("jpackage.app-path")?.let(Path::of)
            val relay = RelayWorker.locate(paths, launcher?.parent)
            // `usage-relay setup` keeps its record in the same folder; with it, the worker publishes to the synced folder.
            val worker = RelayWorker(relay, paths.stateDir.resolve("usage-relay.json"), setupRecord = paths.stateDir.resolve("setup.json"))
            val autostart = launcher?.let { Autostart.forCurrentOS("$it --tray", paths.home) }
            return DesktopServices(paths, store, consent, DesktopUsage(worker, consent, claude::fetch, codex::fetch, publishes), worker, relay, autostart,
                                   UpdateCheck(transport, APP_VERSION, store))
        }
    }
}
