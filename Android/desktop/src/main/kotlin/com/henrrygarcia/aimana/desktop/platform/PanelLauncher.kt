package com.henrrygarcia.aimana.desktop.platform

import java.nio.file.Files
import java.nio.file.Path

/// Starts the panel as its own process, so all of Compose's memory goes back to the OS when the panel closes. The
/// tray never starts a second panel while one is open.
class PanelLauncher(
    private val base: List<String>,
    /// Where the running panel looks for requests ("open the panel", "open settings") from the tray.
    private val requestDir: Path? = null,
    private val start: (List<String>) -> Running = ::startProcess,
) {
    interface Running {
        fun isAlive(): Boolean
        fun stop()
        fun waitFor()
    }

    private var current: Running? = null

    @Synchronized fun open(mode: String) {
        if (current?.isAlive() == true) {
            // Already open: ask it to come to the front (and switch to settings if that was asked).
            requestDir?.let { runCatching { Files.createDirectories(it); Files.writeString(it.resolve(REQUEST), mode) } }
            return
        }
        current = start(base + mode)
    }

    /// Quitting the tray closes the panel too: nothing is left running.
    @Synchronized fun closeAll() { current?.takeIf { it.isAlive() }?.stop() }

    /// Blocks until the open panel exits (window-app mode, without a tray).
    fun waitForPanel() { synchronized(this) { current }?.waitFor() }

    companion object {
        private const val REQUEST = "panel-request"

        /// The pending request for the running panel, consumed once.
        fun takeRequest(dir: Path): String? {
            val file = dir.resolve(REQUEST)
            val mode = runCatching { Files.readString(file).trim() }.getOrNull() ?: return null
            Files.deleteIfExists(file)
            return mode
        }

        /// The installed launcher (jpackage sets `jpackage.app-path`), or the current JVM and classpath in development.
        fun baseCommand(launcher: Path? = System.getProperty("jpackage.app-path")?.let(Path::of),
                        javaHome: String = System.getProperty("java.home"),
                        classPath: String = System.getProperty("java.class.path"),
                        mainClass: String = "com.henrrygarcia.aimana.desktop.MainKt"): List<String> =
            if (launcher != null) listOf(launcher.toString())
            else listOf(Path.of(javaHome, "bin", "java").toString(), "-Xmx256m", "-cp", classPath, mainClass)

        private fun startProcess(command: List<String>): Running {
            val process = ProcessBuilder(command).redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD).start()
            return object : Running {
                override fun isAlive() = process.isAlive
                override fun stop() { process.descendants().forEach { it.destroy() }; process.destroy() }
                override fun waitFor() { process.waitFor() }
            }
        }
    }
}
