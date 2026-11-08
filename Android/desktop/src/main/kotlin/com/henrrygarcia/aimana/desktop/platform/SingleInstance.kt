package com.henrrygarcia.aimana.desktop.platform

import java.io.Closeable
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.WRITE

/// One tray per user: the first process holds `app.lock`; a second one asks it to open its panel and exits.
class SingleInstance private constructor(private val dir: Path, private val channel: FileChannel, private val lock: FileLock) : Closeable {
    /// True once per request from a second launch.
    fun takeOpenRequest(): Boolean = Files.deleteIfExists(dir.resolve(OPEN_REQUEST))

    override fun close() {
        runCatching { lock.release() }
        runCatching { channel.close() }
    }

    companion object {
        private const val OPEN_REQUEST = "open-request"
        /// The tray's lock (one per user).
        const val APP_LOCK = "app.lock"
        /// The panel process's lock: one panel at a time, even across a tray restart.
        const val PANEL_LOCK = "panel.lock"

        fun acquire(dir: Path, lockName: String = APP_LOCK): SingleInstance? {
            Files.createDirectories(dir)
            val channel = FileChannel.open(dir.resolve(lockName), CREATE, WRITE)
            val lock = try { channel.tryLock() } catch (e: OverlappingFileLockException) { null }
            if (lock == null) { channel.close(); return null }
            return SingleInstance(dir, channel, lock)
        }

        fun requestOpen(dir: Path) {
            Files.createDirectories(dir)
            Files.writeString(dir.resolve(OPEN_REQUEST), "")
        }
    }
}
