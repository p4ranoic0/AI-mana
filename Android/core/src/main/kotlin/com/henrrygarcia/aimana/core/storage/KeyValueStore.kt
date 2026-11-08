package com.henrrygarcia.aimana.core.storage

/// Small non-secret preferences (consent, backoff). Each platform persists them its own way.
interface KeyValueStore {
    fun getDouble(key: String): Double?
    fun putDouble(key: String, value: Double)
    fun getInt(key: String): Int?
    fun putInt(key: String, value: Int)
    fun remove(key: String)
}

class InMemoryKeyValueStore : KeyValueStore {
    private val values = mutableMapOf<String, Number>()
    @Synchronized override fun getDouble(key: String) = values[key]?.toDouble()
    @Synchronized override fun putDouble(key: String, value: Double) { values[key] = value }
    @Synchronized override fun getInt(key: String) = values[key]?.toInt()
    @Synchronized override fun putInt(key: String, value: Int) { values[key] = value }
    @Synchronized override fun remove(key: String) { values.remove(key) }
}
