package com.ampierelabs.afteryou.nativebridge

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-GCM ciphertext in noBackupFilesDir, with the non-exportable key in Android Keystore. */
internal class SecureStore(context: Context) {
    private val directory = File(context.noBackupFilesDir, "after-you-secrets")
    private val keyAlias = "after-you.device-storage.v1"

    @Synchronized
    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setKeySize(256)
                .build())
        }.generateKey()
    }

    private fun file(name: String): AtomicFile {
        require(BridgePolicy.validStorageName(name))
        check(directory.isDirectory || directory.mkdirs())
        return AtomicFile(File(directory, "$name.store"))
    }

    @Synchronized
    fun put(name: String, value: String) {
        require(BridgePolicy.validStorageValue(value))
        val target = file(name)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val envelope = "1:${Base64.encodeToString(cipher.iv, Base64.NO_WRAP)}:${Base64.encodeToString(encrypted, Base64.NO_WRAP)}"
        val output = target.startWrite()
        try {
            output.write(envelope.toByteArray(Charsets.UTF_8))
            target.finishWrite(output)
        } catch (failure: Exception) {
            target.failWrite(output)
            throw failure
        }
    }

    @Synchronized
    fun get(name: String): String? {
        val target = file(name)
        // openRead also recovers AtomicFile's backup after an interrupted write.
        val envelope = try { target.openRead().use { String(it.readBytes(), Charsets.UTF_8) } }
            catch (_: FileNotFoundException) { return null }
        val parts = envelope.split(":")
        check(parts.size == 3 && parts[0] == "1")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val nonce = Base64.decode(parts[1], Base64.NO_WRAP)
        check(nonce.size == 12)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, nonce))
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(Base64.decode(parts[2], Base64.NO_WRAP)), Charsets.UTF_8)
    }

    @Synchronized
    fun remove(name: String) = file(name).delete()
}
