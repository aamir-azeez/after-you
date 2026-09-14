package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.system.Os
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

/** Explicit cache erasure on a synthetic, UUID-owned test sandbox; never real game/cache/vault data. */
class PhotoCachePurgeDeviceTest {
    @Test fun moreThanOneBatchLeavesRetryableRemainderThenFinishes() = withContext { context ->
        val kept = File(context.cacheDir, "after-you-photo-kept").apply { mkdir() }
        repeat(1025) { File(kept, "orphan-$it").writeBytes(byteArrayOf(1)) }
        assertFalse(PhotoCache(context).clearAll())
        assertEquals(1, kept.listFiles()!!.size)
        assertTrue(PhotoCache(context).clearAll())
        assertTrue(kept.listFiles()!!.isEmpty())
    }

    @Test fun clearErasesAllPhotoFilesIncludingUnjournaledAndNestedWhilePreservingSiblings() = withContext { context ->
        val raw = PhotoCaptureFiles.directory(context)
        File(raw, "orphan-raw.bin").writeBytes(byteArrayOf(1))
        val kept = File(context.cacheDir, "after-you-photo-kept").apply { mkdir() }
        File(kept, "not-in-a-journal.jpg").writeBytes(byteArrayOf(2))
        val nested = File(kept, "interrupted").apply { mkdir() }
        File(nested, "temporary-image").writeBytes(byteArrayOf(3))
        val sibling = File(context.cacheDir, "synthetic-save").apply { writeText("unchanged") }
        assertTrue(PhotoCachePurge.clearRaw(context))
        assertTrue(PhotoCache(context).clearAll())
        assertTrue(raw.listFiles()!!.isEmpty())
        assertTrue(kept.listFiles()!!.isEmpty())
        assertEquals("unchanged", sibling.readText())
        assertEquals(1, context.revocations)
        assertTrue(PhotoCachePurge.clearRaw(context))
        assertTrue(PhotoCache(context).clearAll()) // Empty/idempotent retry.
    }

    @Test fun failedRevocationPreservesRawNameAndAllowsExactCleanupRetry() = withContext { context ->
        val raw = File(PhotoCaptureFiles.directory(context), "orphan.jpg").apply { writeBytes(byteArrayOf(1)) }
        context.rejectRevocation = true
        assertFalse(PhotoCachePurge.clearRaw(context))
        assertTrue(raw.exists())
        context.rejectRevocation = false
        assertTrue(PhotoCachePurge.clearRaw(context))
        assertFalse(raw.exists())
    }

    @Test fun unwritablePhotoDirectoryFailsThenSucceedsAfterStorageRecovers() = withContext { context ->
        val kept = File(context.cacheDir, "after-you-photo-kept").apply { mkdir() }
        val photo = File(kept, "orphan.jpg").apply { writeBytes(byteArrayOf(2)) }
        Os.chmod(kept.path, 0x140) // 0500: owner can read/traverse but cannot unlink children.
        try {
            assertFalse(PhotoCache(context).clearAll())
            assertTrue(photo.exists())
        } finally { Os.chmod(kept.path, 0x1c0) }
        assertTrue(PhotoCache(context).clearAll())
        assertFalse(photo.exists())
    }

    @Test fun symlinkCannotRedirectPhotoCleanupIntoOtherData() = withContext { context ->
        val outside = File(context.cacheDir, "synthetic-other-data").apply { mkdir() }
        val keep = File(outside, "preserved").apply { writeText("synthetic") }
        val root = File(context.cacheDir, "after-you-photo-kept")
        Os.symlink(outside.path, root.path)
        try {
            assertFalse(PhotoCache(context).clearAll())
            assertEquals("synthetic", keep.readText())
        } finally { check(root.delete()) } // Unlink this test-owned link, never its target.
        check(root.mkdir())
        val child = File(root, "redirect.jpg")
        Os.symlink(keep.path, child.path)
        try {
            assertFalse(PhotoCache(context).clearAll())
            assertEquals("synthetic", keep.readText())
        } finally { check(child.delete()) }
        assertTrue(PhotoCache(context).clearAll())
    }

    private class TestContext(base: Context, private val folder: File) : ContextWrapper(base) {
        var revocations = 0
        var rejectRevocation = false
        override fun getCacheDir() = folder
        override fun revokeUriPermission(uri: Uri, modeFlags: Int) {
            if (rejectRevocation) throw IllegalStateException("Synthetic retryable grant failure")
            require(uri.authority == "$packageName.afteryou.photos")
            revocations++
        }
    }

    private fun withContext(test: (TestContext) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val parent = PhotoCaptureFiles.directory(base)
        val folder = File(parent, "purge-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        try { test(TestContext(base, folder)) } finally {
            check(folder.canonicalFile.parentFile == parent.canonicalFile)
            folder.deleteRecursively()
        }
    }
}
