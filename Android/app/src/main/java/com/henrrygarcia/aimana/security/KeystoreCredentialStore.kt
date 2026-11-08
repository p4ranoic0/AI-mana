package com.henrrygarcia.aimana.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.henrrygarcia.aimana.core.storage.CredentialStore
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

interface SecretCipher {
    fun encrypt(plain: ByteArray): ByteArray
    fun decrypt(blob: ByteArray): ByteArray
    /// Forgets a key Android invalidated, so the next `encrypt` creates a new one.
    fun reset() {}
}

/// AES-256-GCM with a key that never leaves the Android Keystore (no biometric gate: refreshes run unattended).
/// The blob is `iv (12 bytes) + ciphertext`.
class AndroidKeystoreCipher(private val alias: String) : SecretCipher {
    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    override fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return cipher.iv + cipher.doFinal(plain)
    }

    override fun decrypt(blob: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, blob, 0, 12)) }
        return cipher.doFinal(blob, 12, blob.size - 12)
    }

    /// An invalidated key stays in the Keystore and keeps failing: delete it so `key()` generates a new one.
    override fun reset() {
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias) }
    }
}

/// This phone's sign-in sessions and API keys, as one encrypted JSON blob outside backups (`noBackupFilesDir`). If
/// Android invalidated the key (for example after the screen lock changed), the blob is unreadable: it is dropped and
/// the user simply signs in again.
class KeystoreCredentialStore(private val file: File, private val cipher: SecretCipher) : CredentialStore {
    constructor(context: Context) : this(File(context.noBackupFilesDir, "credentials.bin"), AndroidKeystoreCipher("aimana.credentials"))

    @Synchronized private fun load(): MutableMap<String, String> {
        if (!file.exists()) return mutableMapOf()
        return try {
            val text = cipher.decrypt(file.readBytes()).decodeToString()
            (Json.parseToJsonElement(text) as JsonObject).mapValues { (it.value as JsonPrimitive).content }.toMutableMap()
        } catch (e: GeneralSecurityException) {
            file.delete()
            cipher.reset()
            mutableMapOf()
        } catch (e: IllegalArgumentException) {   // not JSON any more
            file.delete()
            mutableMapOf()
        }
    }

    @Synchronized private fun save(values: Map<String, String>) {
        if (values.isEmpty()) { file.delete(); return }
        val temp = File(file.parentFile, file.name + ".tmp")
        val plain = JsonObject(values.mapValues { JsonPrimitive(it.value) }).toString().toByteArray()
        // A key invalidated since the last read: recreate it once (the old blob is unreadable anyway).
        val blob = try { cipher.encrypt(plain) } catch (e: GeneralSecurityException) { cipher.reset(); cipher.encrypt(plain) }
        temp.writeBytes(blob)
        if (!temp.renameTo(file)) { file.delete(); temp.renameTo(file) }
    }

    override fun read(key: String): String? = load()[key]
    @Synchronized override fun write(value: String, key: String) = save(load().also { it[key] = value })
    @Synchronized override fun delete(key: String) = save(load().also { it.remove(key) })
}
