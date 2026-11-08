package com.henrrygarcia.aimana.desktop

import com.henrrygarcia.aimana.desktop.platform.PanelLauncher
import com.henrrygarcia.aimana.desktop.platform.SingleInstance
import com.henrrygarcia.aimana.desktop.ui.Strings
import java.awt.Color
import java.awt.MenuItem
import java.awt.PopupMenu
import java.awt.RenderingHints
import java.awt.SystemTray
import java.awt.TrayIcon
import java.awt.image.BufferedImage
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess
import kotlinx.coroutines.runBlocking

/// The process that stays running: an AWT tray icon (no Compose, so it idles light) that keeps the relay published and
/// starts the panel as a separate process on demand. It never calls a provider directly in the background.
fun runTray(services: DesktopServices, instance: SingleInstance, openPanelAtStart: Boolean) {
    val strings = Strings()
    val panel = PanelLauncher(PanelLauncher.baseCommand(), requestDir = services.paths.stateDir)
    if (!SystemTray.isSupported()) {
        // No tray (some Linux desktops): behave like a window app, and quit when its window closes.
        panel.open("--panel")
        panel.waitForPanel()
        instance.close()
        exitProcess(0)
    } else {
        val menu = PopupMenu().apply {
            add(MenuItem(strings["tray.open"]).apply { addActionListener { panel.open("--panel") } })
            add(MenuItem(strings["tray.settings"]).apply { addActionListener { panel.open("--settings") } })
            addSeparator()
            add(MenuItem(strings["tray.quit"]).apply { addActionListener { panel.closeAll(); instance.close(); exitProcess(0) } })
        }
        val icon = TrayIcon(trayImage(SystemTray.getSystemTray().trayIconSize.width), strings["tray.tooltip"], menu).apply {
            isImageAutoSize = true
            addActionListener { panel.open("--panel") }
        }
        SystemTray.getSystemTray().add(icon)
    }
    if (openPanelAtStart) panel.open("--panel")

    val scheduler = Executors.newSingleThreadScheduledExecutor { Thread(it, "aimana-tray").apply { isDaemon = false } }
    // A second launch (Start menu, double click) asks this one to open the panel.
    scheduler.scheduleWithFixedDelay({ if (instance.takeOpenRequest()) panel.open("--panel") }, 1, 1, TimeUnit.SECONDS)
    // Keep the local sources (statusline, Codex logs, costs) published for the panel and, when set up, for the phone.
    scheduler.execute(object : Runnable {
        override fun run() {
            runCatching { runBlocking { services.worker.publishOnce() } }
            scheduler.schedule(this, services.intervalMinutes.toLong(), TimeUnit.MINUTES)
        }
    })
}

/// A filled ring that reads at 16 px on light and dark task bars.
private fun trayImage(size: Int): BufferedImage {
    val px = size.coerceAtLeast(16)
    return BufferedImage(px, px, BufferedImage.TYPE_INT_ARGB).apply {
        createGraphics().apply {
            setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            color = Color(0x6E, 0x56, 0xCF)
            fillOval(0, 0, px - 1, px - 1)
            color = Color.WHITE
            fillOval(px / 4, px / 4, px / 2, px / 2)
            dispose()
        }
    }
}
