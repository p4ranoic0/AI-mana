package com.henrrygarcia.aimana.desktop.platform

import java.nio.file.Files
import java.nio.file.Path

/// Opens AI·mana at login for this user.
interface Autostart {
    fun isEnabled(): Boolean
    fun enable()
    fun disable()

    companion object {
        fun forCurrentOS(command: String, home: Path): Autostart =
            if (System.getProperty("os.name").startsWith("Windows")) WindowsAutostart(command)
            else LinuxAutostart(home.resolve(".config/autostart"), command)
    }
}

/// `HKCU\...\Run\AImana`, through `reg.exe` (no admin rights needed).
class WindowsAutostart(private val command: String, private val run: (List<String>) -> Int = ::runQuietly) : Autostart {
    private val key = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"

    /// The executable is quoted so a path with spaces still starts; arguments follow.
    private val value: String get() {
        val exe = command.substringBefore(" --")
        return "\"$exe\"" + command.removePrefix(exe)
    }

    override fun isEnabled() = run(listOf("reg", "query", key, "/v", "AImana")) == 0
    override fun enable() { run(listOf("reg", "add", key, "/v", "AImana", "/t", "REG_SZ", "/d", value, "/f")) }
    override fun disable() { run(listOf("reg", "delete", key, "/v", "AImana", "/f")) }
}

/// `~/.config/autostart/aimana.desktop` (XDG autostart, honoured by GNOME, KDE and most desktops).
class LinuxAutostart(private val dir: Path, private val command: String) : Autostart {
    private val file: Path get() = dir.resolve("aimana.desktop")
    override fun isEnabled() = Files.isRegularFile(file)
    override fun enable() {
        Files.createDirectories(dir)
        Files.writeString(file, "[Desktop Entry]\nType=Application\nName=AI·mana\nExec=$command\nX-GNOME-Autostart-enabled=true\n")
    }
    override fun disable() { Files.deleteIfExists(file) }
}

internal fun runQuietly(command: List<String>): Int = runCatching {
    ProcessBuilder(command).redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD)
        .start().waitFor()
}.getOrDefault(-1)
