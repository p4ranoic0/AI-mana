package com.henrrygarcia.aimana.core.storage

import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermissions
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/// The desktop app's small preferences (consent, backoff, settings) as one JSON file, written atomically. Never holds
/// secrets. Re-read on every access so the app and a second process (the `--check` smoke run) agree.
class FileKeyValueStore(private val file: Path) : KeyValueStore {
    private val json = Json { prettyPrint = true }

    @Synchronized private fun load(): MutableMap<String, Double> = runCatching {
        (Json.parseToJsonElement(Files.readAllBytes(file).decodeToString()) as JsonObject)
            .mapNotNull { (k, v) -> (v as? JsonPrimitive)?.doubleOrNull?.let { k to it } }.toMap().toMutableMap()
    }.getOrDefault(mutableMapOf())

    @Synchronized private fun save(values: Map<String, Double>) {
        Files.createDirectories(file.parent)
        // A temporary file of its own, so two writers never rename each other's half-written file.
        val temp = Files.createTempFile(file.parent, file.fileName.toString(), ".tmp")
        try {
            Files.write(temp, json.encodeToString(JsonObject.serializer(), JsonObject(values.mapValues { JsonPrimitive(it.value) })).toByteArray())
            runCatching { Files.setPosixFilePermissions(temp, PosixFilePermissions.fromString("rw-------")) }   // no-op on Windows
            Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    /// Read-modify-write under a lock shared by every process (panel, tray, `--check`): a write from a stale copy can
    /// never bring back a consent that was just revoked.
    private fun update(change: (MutableMap<String, Double>) -> Unit) {
        Files.createDirectories(file.parent)
        // File locks are per JVM: other instances in this process wait on the in-process lock, other processes on the file.
        synchronized(inProcessLock(file)) {
            FileChannel.open(file.resolveSibling(file.fileName.toString() + ".lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { channel ->
                channel.lock().use { save(load().also(change)) }
            }
        }
    }

    private companion object {
        private val locks = java.util.concurrent.ConcurrentHashMap<Path, Any>()
        fun inProcessLock(file: Path): Any = locks.computeIfAbsent(file.toAbsolutePath().normalize()) { Any() }
    }

    override fun getDouble(key: String) = load()[key]
    override fun putDouble(key: String, value: Double) = update { it[key] = value }
    override fun getInt(key: String) = load()[key]?.toInt()
    override fun putInt(key: String, value: Int) = update { it[key] = value.toDouble() }
    override fun remove(key: String) = update { it.remove(key) }
}
