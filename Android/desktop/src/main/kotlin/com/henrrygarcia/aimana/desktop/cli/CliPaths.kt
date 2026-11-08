package com.henrrygarcia.aimana.desktop.cli

import java.nio.file.Path

/// Where the CLIs and AI·mana keep their files on this computer (Windows or Linux).
data class CliPaths(val home: Path, val env: Map<String, String>, val isWindows: Boolean) {
    /// `CODEX_HOME`, or `~/.codex`.
    val codexHome: Path get() = env["CODEX_HOME"]?.takeIf { it.isNotBlank() }?.let(Path::of) ?: home.resolve(".codex")

    /// The first `CLAUDE_CONFIG_DIR` entry, or `~/.claude`.
    val claudeConfigDir: Path get() =
        env["CLAUDE_CONFIG_DIR"]?.split(",")?.firstOrNull()?.takeIf { it.isNotBlank() }?.let(Path::of) ?: home.resolve(".claude")

    /// The relay's own state folder: `%LOCALAPPDATA%\AImana` or `${XDG_DATA_HOME:-~/.local/share}/aimana`.
    val stateDir: Path get() = if (isWindows) {
        (env["LOCALAPPDATA"]?.takeIf { it.isNotBlank() }?.let(Path::of) ?: home.resolve("AppData/Local")).resolve("AImana")
    } else {
        (env["XDG_DATA_HOME"]?.takeIf { it.isNotBlank() }?.let(Path::of) ?: home.resolve(".local/share")).resolve("aimana")
    }

    companion object {
        fun current(): CliPaths {
            val windows = System.getProperty("os.name").startsWith("Windows")
            val env = System.getenv()
            val home = (if (windows) env["USERPROFILE"] else null) ?: System.getProperty("user.home")
            return CliPaths(Path.of(home), env, windows)
        }
    }
}
