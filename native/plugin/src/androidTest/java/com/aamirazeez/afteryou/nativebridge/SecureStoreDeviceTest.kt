package com.aamirazeez.afteryou.nativebridge

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class SecureStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun roundTripOverwriteDeleteAndCiphertext() {
        val store = SecureStore(context)
        val sample = "synthetic-device-token-0123456789"
        try {
            store.put("test_token", sample)
            assertEquals(sample, store.get("test_token"))
            val ciphertext = File(context.noBackupFilesDir, "after-you-secrets/test_token.store").readText()
            assertFalse(ciphertext.contains(sample))
            store.put("test_token", "replacement")
            assertEquals("replacement", store.get("test_token"))
            store.remove("test_token")
            assertNull(store.get("test_token"))
        } finally { store.remove("test_token") }
    }

    @Test fun ciphertextCannotBeMovedToAnotherCredentialName() {
        val store = SecureStore(context)
        try {
            store.put("test_source", "synthetic-only")
            val directory = File(context.noBackupFilesDir, "after-you-secrets")
            File(directory, "test_source.store").copyTo(File(directory, "test_target.store"), overwrite = true)
            try {
                store.get("test_target")
                fail("AES-GCM authentication must reject a credential moved to a different name")
            } catch (_: javax.crypto.AEADBadTagException) { /* Expected AAD mismatch. */ }
        } finally {
            store.remove("test_source")
            store.remove("test_target")
        }
    }
}
