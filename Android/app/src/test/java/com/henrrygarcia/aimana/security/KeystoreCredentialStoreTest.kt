package com.henrrygarcia.aimana.security

import java.io.File
import java.nio.file.Files
import java.security.KeyStoreException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/// Reversible stand-in for the Keystore cipher; `broken` simulates a key Android invalidated.
private class FakeCipher(var broken: Exception? = null) : SecretCipher {
    override fun encrypt(plain: ByteArray) = plain.reversedArray() + byteArrayOf(42)
    override fun decrypt(blob: ByteArray): ByteArray { broken?.let { throw it }; return blob.dropLast(1).toByteArray().reversedArray() }
}

/// A key Android invalidated permanently: it fails to encrypt and decrypt until the alias is recreated.
private class InvalidatedKeyCipher : SecretCipher {
    var dead = true
    var resets = 0
    override fun encrypt(plain: ByteArray): ByteArray {
        if (dead) throw java.security.InvalidKeyException("key permanently invalidated")
        return plain.reversedArray()
    }
    override fun decrypt(blob: ByteArray): ByteArray {
        if (dead) throw java.security.InvalidKeyException("key permanently invalidated")
        return blob.reversedArray()
    }
    override fun reset() { dead = false; resets++ }
}

class KeystoreCredentialStoreTest {
    private val dir: File = Files.createTempDirectory("aimana-keystore-test").toFile()
    private val file = File(dir, "credentials.bin")

    @Test fun roundTripThroughCipher() {
        val store = KeystoreCredentialStore(file, FakeCipher())
        store.write("session-json", "claude.phone.session")
        assertEquals("session-json", KeystoreCredentialStore(file, FakeCipher()).read("claude.phone.session"))
        assertFalse(file.readText(Charsets.ISO_8859_1).contains("session-json"))   // never stored in the clear
    }

    @Test fun unreadableBlobReadsAsSignedOut() {
        KeystoreCredentialStore(file, FakeCipher()).write("session-json", "claude.phone.session")
        for (failure in listOf(AEADBadTagException("tag"), KeyStoreException("invalidated"))) {
            val store = KeystoreCredentialStore(file, FakeCipher(broken = failure))
            assertNull(store.read("claude.phone.session"))
            assertFalse(file.exists())                    // the dead blob is dropped: sign in again
            KeystoreCredentialStore(file, FakeCipher()).write("session-json", "claude.phone.session")
        }
    }

    @Test fun deleteRemovesOnlyThatKey() {
        val store = KeystoreCredentialStore(file, FakeCipher())
        store.write("a", "claude.phone.session")
        store.write("b", "deepseek.apiKey")
        store.delete("claude.phone.session")
        assertNull(store.read("claude.phone.session"))
        assertEquals("b", store.read("deepseek.apiKey"))
    }

    @Test fun invalidatedKeyIsRecreatedSoTheNextSignInWorks() {
        file.writeBytes(byteArrayOf(1, 2, 3))   // a blob written with the old key
        val cipher = InvalidatedKeyCipher()
        val store = KeystoreCredentialStore(file, cipher)
        assertNull(store.read("claude.phone.session"))
        store.write("new-session", "claude.phone.session")   // same store, same process: must not fail
        assertEquals("new-session", store.read("claude.phone.session"))
        assertEquals(1, cipher.resets)
    }

    @Test fun invalidatedKeyFoundWhileSavingIsRecreated() {
        val cipher = InvalidatedKeyCipher()
        KeystoreCredentialStore(file, cipher).write("new-session", "claude.phone.session")
        assertEquals("new-session", KeystoreCredentialStore(file, cipher).read("claude.phone.session"))
    }
}
