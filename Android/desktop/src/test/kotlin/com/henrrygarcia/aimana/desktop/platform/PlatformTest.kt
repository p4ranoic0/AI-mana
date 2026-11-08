package com.henrrygarcia.aimana.desktop.platform

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlatformTest {
    private val dir = Files.createTempDirectory("aimana-platform-test")

    @Test fun secondInstanceDefersToFirst() {
        val first = SingleInstance.acquire(dir)
        assertNotNull(first)
        assertNull(SingleInstance.acquire(dir))       // a second process gives up...
        SingleInstance.requestOpen(dir)                // ...and asks the first to open its panel
        assertTrue(first!!.takeOpenRequest())
        assertFalse(first.takeOpenRequest())           // consumed once
        first.close()
        assertNotNull(SingleInstance.acquire(dir))     // free again after the first exits
    }

    @Test fun linuxAutostartRoundTrip() {
        val autostart = LinuxAutostart(dir.resolve("autostart"), command = "/opt/aimana/bin/AImana --tray")
        assertFalse(autostart.isEnabled())
        autostart.enable()
        assertTrue(autostart.isEnabled())
        val desktop = Files.readString(dir.resolve("autostart/aimana.desktop"))
        assertTrue(desktop.contains("Exec=/opt/aimana/bin/AImana --tray"))
        autostart.disable()
        assertFalse(autostart.isEnabled())
    }

    @Test fun windowsAutostartUsesTheRunKey() {
        val calls = mutableListOf<List<String>>()
        var present = false
        val autostart = WindowsAutostart(command = "C:\\AImana\\AImana.exe --tray") { args ->
            calls += args
            when (args[1]) { "add" -> { present = true; 0 }; "delete" -> { present = false; 0 }; else -> if (present) 0 else 1 }
        }
        autostart.enable()
        assertEquals(listOf("reg", "add", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "AImana", "/t", "REG_SZ",
                            "/d", "\"C:\\AImana\\AImana.exe\" --tray", "/f"), calls.last())
        assertTrue(autostart.isEnabled())
        autostart.disable()
        assertFalse(autostart.isEnabled())
    }
}
