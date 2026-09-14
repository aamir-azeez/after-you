package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID

/** Synthetic storage tests; actual recreation/process-death camera flows use the test Activity. */
class PhotoLifecycleDeviceTest {
    @Test fun requestCodesSurviveAllocatorRecreationWithoutReuse() = withContext { context ->
        val first = PhotoCameraRequestCodes(context).reserve()
        val second = PhotoCameraRequestCodes(context).reserve()
        assertEquals(first + 1, second)
        assertTrue(first in PhotoCameraRequestCodes.FIRST..PhotoCameraRequestCodes.LAST)
    }

    @Test fun corruptAndExhaustedRequestCountersFailWithoutResetting() = withContext { context ->
        val counter = File(context.noBackupFilesDir, "after-you-photo-request-code")
        for (bytes in listOf(byteArrayOf(7), ByteBuffer.allocate(4).putInt(PhotoCameraRequestCodes.LAST + 1).array())) {
            counter.writeBytes(bytes)
            try { PhotoCameraRequestCodes(context).reserve(); fail("Unsafe counter must not reset") } catch (_: IllegalStateException) { }
            assertArrayEquals(bytes, counter.readBytes())
        }
    }

    @Test fun startupCleanupRevokesOnlyOwnedRawOutputAndPreservesOtherFiles() = withContext { context ->
        val root = PhotoCaptureFiles.directory(context)
        val raw = File(root, "0123456789abcdef0123456789abcdef.jpg").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val unrelated = File(root, "not-a-photo.jpg").apply { writeText("synthetic untouched") }
        val kept = File(context.cacheDir, "after-you-photo-kept").apply { mkdir() }
        val keptFile = File(kept, "fedcba9876543210fedcba9876543210.jpg").apply { writeBytes(byteArrayOf(4)) }
        assertTrue(PhotoCaptureFiles.cleanupInterrupted(context))
        assertFalse(raw.exists())
        assertTrue(unrelated.exists())
        assertTrue(keptFile.exists())
        assertEquals(1, context.revocations)
        assertTrue(PhotoCaptureFiles.cleanupInterrupted(context))
        assertEquals(1, context.revocations)
    }

    private class TestContext(base: Context, private val folder: File) : ContextWrapper(base) {
        var revocations = 0
        override fun getCacheDir() = folder
        override fun getNoBackupFilesDir() = File(folder, "no-backup").apply { mkdir() }
        override fun revokeUriPermission(uri: Uri, modeFlags: Int) {
            require(uri.authority == "$packageName.afteryou.photos")
            revocations++ // No real platform grant is created/altered by this synthetic storage test.
        }
    }

    private fun withContext(test: (TestContext) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        // Under the real provider's raw path so getUriForFile resolves it, but still uniquely owned.
        val parent = PhotoCaptureFiles.directory(base)
        val folder = File(parent, "lifecycle-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        try { test(TestContext(base, folder)) } finally {
            check(folder.canonicalFile.parentFile == parent.canonicalFile)
            folder.deleteRecursively()
        }
    }
}
