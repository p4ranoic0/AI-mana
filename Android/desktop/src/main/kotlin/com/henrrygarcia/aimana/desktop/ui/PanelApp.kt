package com.henrrygarcia.aimana.desktop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindow
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberDialogState
import androidx.compose.ui.window.rememberWindowState
import com.henrrygarcia.aimana.core.AppUpdate
import com.henrrygarcia.aimana.core.DirectProvider
import com.henrrygarcia.aimana.desktop.DesktopServices
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/// The panel process (`--panel` or `--settings`): Compose windows only, started by the tray on demand. It refreshes when
/// it opens and while it stays open, and exits when its last window closes, so all of its memory goes back to the OS.
fun runPanelApp(services: DesktopServices, startWithSettings: Boolean) = application {
    val strings = remember { Strings() }
    var rows by remember { mutableStateOf<List<PanelRow>>(emptyList()) }
    var relayProblem by remember { mutableStateOf<String?>(null) }
    var updated by remember { mutableStateOf<Instant?>(null) }
    var update by remember { mutableStateOf(services.updates.available()) }
    var panelOpen by remember { mutableStateOf(!startWithSettings) }
    var settingsOpen by remember { mutableStateOf(startWithSettings) }
    var refreshTick by remember { mutableStateOf(0) }
    var generation by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        val mine = ++generation
        val states = services.usage.refresh()
        // A newer refresh (e.g. after a consent change) started meanwhile: this result is stale.
        if (mine != generation) return
        rows = panelRows(states, strings, Instant.now())
        relayProblem = services.usage.relayProblem
        updated = Instant.now()
        update = services.updates.refresh()
    }

    LaunchedEffect(refreshTick) {
        while (true) {
            refresh()
            delay(services.intervalMinutes * 60_000L)
        }
    }
    var frontTick by remember { mutableStateOf(0) }
    // The tray asks an open panel to come forward instead of starting another one.
    LaunchedEffect(Unit) {
        while (true) {
            when (com.henrrygarcia.aimana.desktop.platform.PanelLauncher.takeRequest(services.paths.stateDir)) {
                "--settings" -> { settingsOpen = true; frontTick++ }
                "--panel" -> { panelOpen = true; frontTick++ }
            }
            delay(500)
        }
    }
    if (!panelOpen && !settingsOpen) exitApplication()

    if (panelOpen) {
        Window(onCloseRequest = { panelOpen = false }, title = strings["panel.title"], alwaysOnTop = true,
               state = rememberWindowState(size = DpSize(360.dp, 420.dp), position = WindowPosition(Alignment.BottomEnd))) {
            LaunchedEffect(frontTick) { window.toFront(); window.requestFocus() }
            AppTheme {
                Panel(rows, relayProblem, updated, update, strings,
                      onRefresh = { scope.launch { refresh() } }, onSettings = { settingsOpen = true })
            }
        }
    }
    if (settingsOpen) {
        Window(onCloseRequest = { settingsOpen = false }, title = strings["settings.title"],
               state = rememberWindowState(size = DpSize(440.dp, 460.dp))) {
            LaunchedEffect(frontTick) { window.toFront(); window.requestFocus() }
            AppTheme {
                Settings(services, strings, onChanged = { refreshTick++ }, onClose = { settingsOpen = false },
                         onUpdatesChanged = { update = services.updates.available() })
            }
        }
    }
}

@Composable
private fun AppTheme(content: @Composable () -> Unit) {
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
        Surface(Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.background) { content() }
    }
}

@Composable
private fun Panel(rows: List<PanelRow>, relayProblem: String?, updated: Instant?, update: AppUpdate?, strings: Strings,
                  onRefresh: () -> Unit, onSettings: () -> Unit) {
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // An install that fell behind says so instead of breaking silently.
        update?.let { available ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(strings.format("panel.update", available.version), style = MaterialTheme.typography.bodySmall,
                     modifier = Modifier.weight(1f))
                TextButton(onClick = { openInBrowser(available.pageUrl) }) { Text(strings["panel.updateDownload"]) }
            }
            HorizontalDivider()
        }
        for (row in rows) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(row.name, style = MaterialTheme.typography.titleSmall)
                        row.asOf?.let { Text(it, style = MaterialTheme.typography.labelSmall) }
                    }
                    Text(row.headline ?: "–", style = MaterialTheme.typography.titleMedium)
                }
                for (lane in row.lanes) {
                    Row {
                        Text(lane.title, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Text(lane.percent + (lane.reset?.let { " · $it" } ?: ""), style = MaterialTheme.typography.bodySmall)
                    }
                }
                for (line in row.details) Text(line, style = MaterialTheme.typography.bodySmall)
                row.cost?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                row.message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
            }
            HorizontalDivider()
        }
        relayProblem?.let { Text(strings.format("panel.relayProblem", it), style = MaterialTheme.typography.bodySmall) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(updated?.let { strings.format("panel.updated", java.time.format.DateTimeFormatter.ofPattern("HH:mm")
                .withZone(java.time.ZoneId.systemDefault()).format(it)) } ?: "", style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.weight(1f))
            TextButton(onClick = onRefresh) { Text(strings["panel.refresh"]) }
            TextButton(onClick = onSettings) { Text(strings["tray.settings"]) }
        }
    }
}

@Composable
private fun Settings(services: DesktopServices, strings: Strings, onChanged: () -> Unit, onClose: () -> Unit,
                     onUpdatesChanged: () -> Unit) {
    var version by remember { mutableStateOf(0) }   // re-reads the consent after the notice
    var pending by remember { mutableStateOf<DirectProvider?>(null) }
    var autostartOn by remember { mutableStateOf(services.autostart?.isEnabled() == true) }
    var updatesOn by remember { mutableStateOf(services.updates.enabled) }
    var interval by remember { mutableStateOf(services.intervalMinutes) }

    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(strings["settings.direct"], style = MaterialTheme.typography.titleSmall)
        for (provider in DirectProvider.entries) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(strings[if (provider == DirectProvider.CLAUDE) "settings.claude" else "settings.codex"], Modifier.weight(1f))
                Text(strings["panel.unofficial"], style = MaterialTheme.typography.labelSmall)
                Spacer(Modifier.width(8.dp))
                Switch(checked = version >= 0 && services.consent.isGranted(provider), onCheckedChange = { on ->
                    if (on) pending = provider else { services.consent.revoke(provider); version++; onChanged() }
                })
            }
        }
        Text(strings["settings.directNote"], style = MaterialTheme.typography.bodySmall)
        HorizontalDivider()
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(strings.format("settings.interval", interval), Modifier.weight(1f))
            TextButton(onClick = { interval = (interval - 1).coerceAtLeast(1); services.intervalMinutes = interval }) { Text("−") }
            TextButton(onClick = { interval = (interval + 1).coerceAtMost(60); services.intervalMinutes = interval }) { Text("+") }
        }
        services.autostart?.let { autostart ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(strings["settings.autostart"], Modifier.weight(1f))
                Switch(checked = autostartOn, onCheckedChange = { on ->
                    if (on) autostart.enable() else autostart.disable()
                    autostartOn = autostart.isEnabled()
                })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(strings["settings.updates"])
                Text(strings["settings.updatesNote"], style = MaterialTheme.typography.bodySmall)
            }
            Switch(checked = updatesOn, onCheckedChange = { on ->
                services.updates.enabled = on
                updatesOn = on
                onUpdatesChanged()
            })
        }
        services.relayBinary?.let { relay ->
            OutlinedButton(onClick = {
                runCatching { ProcessBuilder(relaySetupCommand(relay.toString(), services.paths.isWindows, services.worker.setupOutput)).start() }
            }) { Text(strings["settings.setup"]) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Button(onClick = onClose) { Text(strings["settings.close"]) }
        }
    }

    pending?.let { provider ->
        DialogWindow(onCloseRequest = { pending = null },
                     title = strings[if (provider == DirectProvider.CLAUDE) "notice.claude.title" else "notice.codex.title"],
                     state = rememberDialogState(size = DpSize(480.dp, 380.dp))) {
            AppTheme {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(strings[if (provider == DirectProvider.CLAUDE) "notice.claude" else "notice.codex"],
                         modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        TextButton(onClick = { pending = null }) { Text(strings["notice.cancel"]) }
                        Button(onClick = {
                            services.consent.grant(provider)
                            pending = null
                            version++
                            onChanged()
                        }) { Text(strings["notice.accept"]) }
                    }
                }
            }
        }
    }
}

/// `usage-relay setup` in a visible console, so the user sees what it installs. Never schedules (the tray publishes)
/// and keeps the folder chosen before, when there is one.
fun relaySetupCommand(relay: String, windows: Boolean, output: java.nio.file.Path?): List<String> {
    val setup = listOf(relay, "setup", "--no-schedule") + (output?.let { listOf("--output", it.toString()) } ?: emptyList())
    return if (windows) listOf("cmd", "/c", "start", "\"AI·mana setup\"", "cmd", "/k") + setup
           else listOf("x-terminal-emulator", "-e") + setup
}

/// The release page in the default browser; `xdg-open` where AWT has no browser support (some Linux desktops).
private fun openInBrowser(url: String) {
    val desktop = runCatching { java.awt.Desktop.getDesktop() }.getOrNull()
    if (desktop?.isSupported(java.awt.Desktop.Action.BROWSE) == true) runCatching { desktop.browse(java.net.URI(url)) }
    else runCatching { ProcessBuilder("xdg-open", url).start() }
}
