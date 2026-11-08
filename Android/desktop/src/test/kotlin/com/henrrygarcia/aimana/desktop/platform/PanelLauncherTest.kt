package com.henrrygarcia.aimana.desktop.platform

import java.nio.file.Path
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PanelLauncherTest {
    private class FakeProcess(var alive: Boolean = true) : PanelLauncher.Running {
        var stopped = false
        override fun isAlive() = alive
        override fun stop() { stopped = true; alive = false }
        override fun waitFor() { alive = false }
    }

    @Test fun openWhileAPanelRunsAsksThatPanel() {
        val dir = java.nio.file.Files.createTempDirectory("aimana-panel-request")
        val process = FakeProcess()
        val launcher = PanelLauncher(listOf("AImana.exe"), requestDir = dir) { process }
        launcher.open("--panel")
        launcher.open("--settings")                              // panel already running: ask it instead
        assertEquals("--settings", PanelLauncher.takeRequest(dir))
        assertEquals(null, PanelLauncher.takeRequest(dir))      // consumed once
    }

    @Test fun quittingStopsTheOpenPanel() {
        val process = FakeProcess()
        val launcher = PanelLauncher(listOf("AImana.exe")) { process }
        launcher.open("--panel")
        launcher.closeAll()
        assertTrue(process.stopped)
    }

    @Test fun onlyOnePanelAcrossProcesses() {
        val dir = java.nio.file.Files.createTempDirectory("aimana-panel-lock")
        val first = SingleInstance.acquire(dir, SingleInstance.PANEL_LOCK)
        org.junit.Assert.assertNotNull(first)
        org.junit.Assert.assertNull(SingleInstance.acquire(dir, SingleInstance.PANEL_LOCK))
        org.junit.Assert.assertNotNull(SingleInstance.acquire(dir))   // the tray's own lock is a different one
        first!!.close()
    }

    @Test fun panelLauncherNeverStartsASecondPanel() {
        val started = mutableListOf<List<String>>()
        val process = FakeProcess()
        val launcher = PanelLauncher(listOf("AImana.exe")) { started += it; process }
        launcher.open("--panel")
        launcher.open("--panel")          // still open: nothing new
        assertEquals(1, started.size)
        process.alive = false             // the user closed it
        launcher.open("--settings")
        assertEquals(listOf(listOf("AImana.exe", "--panel"), listOf("AImana.exe", "--settings")), started)
    }

    @Test fun panelCommandUsesTheInstalledLauncher() {
        assertEquals(listOf("C:\\AImana\\app\\AImana.exe"), PanelLauncher.baseCommand(launcher = Path.of("C:\\AImana\\app\\AImana.exe"),
            javaHome = "ignored", classPath = "ignored", mainClass = "ignored"))
    }

    @Test fun devPanelCommandUsesTheCurrentJava() {
        val command = PanelLauncher.baseCommand(launcher = null, javaHome = "/jdk", classPath = "a.jar:b.jar", mainClass = "x.MainKt")
        assertTrue(command.first().replace('\\', '/').startsWith("/jdk/bin/java"))
        assertEquals(listOf("-cp", "a.jar:b.jar", "x.MainKt"), command.drop(1).filter { !it.startsWith("-X") })
    }
}
