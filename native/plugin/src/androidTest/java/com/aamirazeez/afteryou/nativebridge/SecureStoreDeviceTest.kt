package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.ContextWrapper
import android.system.Os
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

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

    @Test fun unreadableCredentialIsNotReportedMissingAndCanBeRetried() = withStore { store, directory ->
        val name = "test_unreadable"
        store.put(name, "synthetic-retained-identity")
        val saved = File(directory, "$name.store")
        Os.chmod(saved.path, 0)
        try { assertStorageFailure { store.get(name) } }
        finally { Os.chmod(saved.path, 0x180) } // 0600
        assertEquals("synthetic-retained-identity", store.get(name))

        // A failed stat of an inaccessible parent must not be mistaken for absence either.
        Os.chmod(directory.path, 0)
        try { assertStorageFailure { store.get(name) } }
        finally { Os.chmod(directory.path, 0x1c0) } // 0700
        assertEquals("synthetic-retained-identity", store.get(name))
        assertNull(store.get("test_genuinely_absent"))
    }

    @Test fun failedDeletionDoesNotAcknowledgeRemainingAtomicFilesAndRetryClearsAll() = withStore { store, directory ->
        val name = "test_delete"
        store.put(name, "synthetic-delete-only")
        val base = File(directory, "$name.store")
        val files = listOf(base, File(base.path + ".new"), File(base.path + ".bak"))
        files.drop(1).forEach { base.copyTo(it) }
        Os.chmod(directory.path, 0x140) // 0500: readable, but child unlink is denied.
        try {
            assertStorageFailure { store.remove(name) }
            files.forEach { assertTrue(it.exists()) }
        } finally { Os.chmod(directory.path, 0x1c0) }
        store.remove(name)
        files.forEach { assertFalse(it.exists()) }
        assertNull(store.get(name))
        store.remove(name) // Successful deletion remains idempotent.
    }

    @Test fun failedAtomicCommitCannotReportStored() = withStore { store, directory ->
        // AtomicFile.finishWrite logs a failed rename instead of throwing. A nonempty
        // synthetic destination directory makes that failure deterministic on Android.
        val destination = File(directory, "test_blocked.store").apply { check(mkdir()) }
        val preserved = File(destination, "unrelated").apply { writeText("keep") }
        assertStorageFailure { store.put("test_blocked", "synthetic-not-committed") }
        assertEquals("keep", preserved.readText())
        check(preserved.delete())
        check(destination.delete())
        store.put("test_blocked", "synthetic-retry")
        assertEquals("synthetic-retry", store.get("test_blocked"))
    }

    private fun assertStorageFailure(work: () -> Unit) {
        var failed = false
        try { work() } catch (_: Exception) { failed = true }
        assertTrue("A storage failure must propagate instead of acknowledging success or absence", failed)
    }

    private fun withStore(work: (SecureStore, File) -> Unit) {
        val base = context
        val folder = File(base.cacheDir, "secure-store-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        val isolated = object : ContextWrapper(base) { override fun getNoBackupFilesDir() = folder }
        val directory = File(folder, "after-you-secrets").apply { check(mkdir()) }
        try { work(SecureStore(isolated), directory) } finally {
            check(folder.canonicalFile.parentFile == base.cacheDir.canonicalFile)
            folder.deleteRecursively()
        }
    }
}
