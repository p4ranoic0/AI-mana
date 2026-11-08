package com.henrrygarcia.aimana.desktop

import com.henrrygarcia.aimana.desktop.platform.SingleInstance
import com.henrrygarcia.aimana.desktop.ui.Strings
import com.henrrygarcia.aimana.desktop.ui.panelRows
import com.henrrygarcia.aimana.desktop.ui.runPanelApp
import java.time.Instant
import kotlin.system.exitProcess
import kotlinx.coroutines.runBlocking

const val APP_VERSION = "1.3.0"

fun main(args: Array<String>) {
    if ("--version" in args) {
        println("AImana $APP_VERSION")
        return
    }
    // CI smoke run: decode a given relay file, no worker and no direct access.
    args.indexOf("--relay-file").takeIf { it >= 0 && it + 1 < args.size }?.let { index ->
        if ("--check" in args) { runBlocking { checkRelayFile(java.nio.file.Path.of(args[index + 1])) }.forEach(::println); return }
    }
    val panelProcess = "--panel" in args || "--settings" in args
    val services = DesktopServices.create(publishes = !panelProcess)
    if ("--check" in args) exitProcess(check(services))
    // The panel and the settings run in their own short-lived process, started by the tray.
    if (panelProcess) {
        // One panel at a time, even when an earlier tray left one open.
        val panelLock = SingleInstance.acquire(services.paths.stateDir, SingleInstance.PANEL_LOCK) ?: return
        panelLock.use { runPanelApp(services, startWithSettings = "--settings" in args) }
        return
    }
    // One tray per user: a second launch asks the running one to open its panel.
    val instance = SingleInstance.acquire(services.paths.stateDir) ?: run {
        SingleInstance.requestOpen(services.paths.stateDir)
        return
    }
    runTray(services, instance, openPanelAtStart = "--tray" !in args)
}

/// No UI: one refresh, printed. The CI smoke test and a quick diagnosis on a user's machine.
private fun check(services: DesktopServices): Int = runBlocking {
    val states = services.usage.refresh()
    services.usage.relayProblem?.let { println("relay: $it") }
    panelRows(states, Strings(), Instant.now()).forEach { row ->
        println("${row.name}: ${row.headline ?: "-"}${row.message?.let { "  ($it)" } ?: ""}")
    }
    0
}

/// The panel's lines for one relay file only (direct access stays off).
suspend fun checkRelayFile(file: java.nio.file.Path): List<String> {
    val consent = com.henrrygarcia.aimana.core.DirectAccessConsent(com.henrrygarcia.aimana.core.storage.InMemoryKeyValueStore())
    val usage = com.henrrygarcia.aimana.desktop.relay.DesktopUsage(com.henrrygarcia.aimana.desktop.relay.RelayWorker(null, file), consent,
        claude = { throw com.henrrygarcia.aimana.core.providers.UsageError.RelayUnavailable },
        codex = { throw com.henrrygarcia.aimana.core.providers.UsageError.RelayUnavailable }, publish = false)
    return panelRows(usage.refresh(), Strings(java.util.Locale.ENGLISH), Instant.now()).map { row ->
        "${row.name}: ${row.headline ?: "-"}${row.message?.let { "  ($it)" } ?: ""}"
    }
}
