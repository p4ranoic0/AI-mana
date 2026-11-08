package com.henrrygarcia.aimana.core.storage

/// Secret storage: this device's sign-in sessions and API keys. Android encrypts it with the Keystore.
interface CredentialStore {
    fun read(key: String): String?
    fun write(value: String, key: String)
    fun delete(key: String)
}

class InMemoryCredentialStore : CredentialStore {
    private val values = mutableMapOf<String, String>()
    @Synchronized override fun read(key: String) = values[key]
    @Synchronized override fun write(value: String, key: String) { values[key] = value }
    @Synchronized override fun delete(key: String) { values.remove(key) }
}
