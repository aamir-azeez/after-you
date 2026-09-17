package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.UUID

/** Synthetic pixels only. No camera, gallery, real photo or existing app cache entry is read. */
@RunWith(AndroidJUnit4::class)
class PhotoImageDeviceTest {
    @Test fun freshAndroidEncoderMetadataCanBeRemoved() {
        val bitmap = Bitmap.createBitmap(40, 30, Bitmap.Config.ARGB_8888)
        val output = ByteArrayOutputStream()
        try { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 80, output)) }
        finally { bitmap.recycle() }
        val bytes = output.toByteArray()
        val stripped = PhotoPolicy.stripEncoderMetadata(bytes)
        assertNotNull("Synthetic Android JPEG header markers: " + headerMarkers(bytes), stripped)
        assertTrue(PhotoPolicy.safeJpeg(requireNotNull(stripped)))
    }

    @Test fun imageIsRotatedResizedCappedAndCameraMetadataIsGone() {
        withFolder { folder ->
            val source = File(folder, "synthetic-source.jpg")
            val bitmap = Bitmap.createBitmap(1600, 1200, Bitmap.Config.ARGB_8888)
            try {
                val row = IntArray(1600)
                var seed = 117
                for (y in 0 until 1200) {
                    for (x in row.indices) { seed = seed * 1664525 + 1013904223; row[x] = Color.rgb(seed ushr 16 and 255, seed ushr 8 and 255, seed and 255) }
                    bitmap.setPixels(row, 0, row.size, 0, y, row.size, 1)
                }
                source.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
            } finally { bitmap.recycle() }
            ExifInterface(source.path).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
                setAttribute(ExifInterface.TAG_MAKE, "Synthetic private camera")
                setAttribute(ExifInterface.TAG_DATETIME, "2001:02:03 04:05:06")
                setAttribute(ExifInterface.TAG_GPS_LATITUDE, "1/1,2/1,3/1")
                setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                saveAttributes()
            }
            val output = PhotoImage.sanitize(source)
            assertTrue(output.jpeg.size <= PhotoAvatarPolicy.MAX_JPEG_BYTES)
            assertEquals(160, output.width)
            assertEquals(160, output.height)
            assertTrue(PhotoPolicy.safeJpeg(output.jpeg))
            val clean = File(folder, "synthetic-clean.jpg").apply { writeBytes(output.jpeg) }
            val exif = ExifInterface(clean.path)
            assertNull(exif.getAttribute(ExifInterface.TAG_MAKE))
            assertNull(exif.getAttribute(ExifInterface.TAG_DATETIME))
            assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
            assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE_REF))
            // Android reports UNDEFINED for a JPEG with no orientation tag; pixels are already rotated.
            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED)
            assertTrue(orientation == ExifInterface.ORIENTATION_UNDEFINED || orientation == ExifInterface.ORIENTATION_NORMAL)
        }
    }

    @Test fun allExifTransformsAreAppliedBeforeCenteredCrop() {
        // Expected corner colors are independent of Android Matrix implementation.
        val colors = intArrayOf(Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW)
        val expected = listOf(
            intArrayOf(0, 1, 2, 3), intArrayOf(1, 0, 3, 2),
            intArrayOf(3, 2, 1, 0), intArrayOf(2, 3, 0, 1),
            intArrayOf(0, 2, 1, 3), intArrayOf(2, 0, 3, 1),
            intArrayOf(3, 1, 2, 0), intArrayOf(1, 3, 0, 2)
        )
        withFolder { folder ->
            for (orientation in 1..8) {
                val source = File(folder, "orientation-$orientation.jpg")
                val bitmap = Bitmap.createBitmap(120, 80, Bitmap.Config.ARGB_8888)
                try {
                    for (y in 0 until 80) for (x in 0 until 120) {
                        val color = if (x < 20 || x >= 100) Color.MAGENTA else colors[(if (y >= 40) 2 else 0) + (if (x >= 60) 1 else 0)]
                        bitmap.setPixel(x, y, color)
                    }
                    source.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it)) }
                } finally { bitmap.recycle() }
                ExifInterface(source.path).apply {
                    setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                    saveAttributes()
                }
                val output = PhotoImage.sanitize(source)
                assertEquals(80, output.width)
                assertEquals(80, output.height)
                val decoded = requireNotNull(BitmapFactory.decodeByteArray(output.jpeg, 0, output.jpeg.size))
                try {
                    val coordinates = listOf(10 to 10, 69 to 10, 10 to 69, 69 to 69)
                    coordinates.forEachIndexed { index, (x, y) ->
                        assertNearColor("Orientation $orientation corner $index", colors[expected[orientation - 1][index]], decoded.getPixel(x, y))
                    }
                } finally { decoded.recycle() }
            }
        }
    }

    @Test fun noisySmallAvatarMeetsNewCapWithoutRelyingOnDownscaleSmoothing() {
        withFolder { folder ->
            val sizes = mutableListOf<Int>()
            for (seed in listOf(7, 117, 90210)) {
                val source = File(folder, "noise-$seed.png")
                val bitmap = noiseBitmap(160, 160, seed)
                try { source.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
                finally { bitmap.recycle() }
                val output = PhotoImage.sanitize(source)
                assertEquals(160, output.width)
                assertEquals(160, output.height)
                assertTrue(output.jpeg.size <= PhotoAvatarPolicy.MAX_JPEG_BYTES)
                assertTrue(PhotoPolicy.safeJpeg(output.jpeg))
                sizes.add(output.jpeg.size)
            }
            // Synthetic output sizes only; no image or camera/account data enters logs.
            android.util.Log.i("AfterYouPhotoSyntheticTest", "160px noise JPEG byte counts: ${sizes.joinToString(",")}")
        }
    }

    @Test fun tinyInputsStaySmallAndAreSquare() {
        withFolder { folder ->
            for ((width, height) in listOf(1 to 1, 40 to 30, 20 to 240, 120 to 80)) {
                val source = File(folder, "small-$width-$height.png")
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.CYAN)
                try { source.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
                finally { bitmap.recycle() }
                val output = PhotoImage.sanitize(source)
                assertEquals(minOf(width, height), output.width)
                assertEquals(output.width, output.height)
                assertTrue(output.jpeg.size <= PhotoAvatarPolicy.MAX_JPEG_BYTES)
            }
        }
    }

    @Test fun priorLargerRectangularPhotosRemainReadable() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = folder
                override fun getNoBackupFilesDir() = File(folder, "durable").apply { mkdirs() }
            }
            // Construct a valid historical payload directly; it must not be re-encoded by the new policy.
            val bitmap = noiseBitmap(400, 300, 117)
            val stream = ByteArrayOutputStream()
            try { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)) }
            finally { bitmap.recycle() }
            val jpeg = requireNotNull(PhotoPolicy.stripEncoderMetadata(stream.toByteArray()))
            assertTrue(jpeg.size > PhotoAvatarPolicy.MAX_JPEG_BYTES)
            val cache = PhotoCache(context)
            val kept = cache.keep(EncodedPhoto(jpeg, 400, 300))
            val read = cache.read(kept.getString("photo_id"))
            assertEquals(400, read.getInt("width"))
            assertEquals(300, read.getInt("height"))
            assertArrayEquals(jpeg, android.util.Base64.decode(read.getString("jpeg_base64"), android.util.Base64.DEFAULT))
        }
    }

    @Test fun acceptedCacheReadDiscardAndPathTraversalRemainBounded() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = folder
                override fun getNoBackupFilesDir() = File(folder, "durable").apply { mkdirs() }
            }
            val raw = File(folder, "synthetic-small.jpg")
            val bitmap = Bitmap.createBitmap(40, 30, Bitmap.Config.ARGB_8888)
            try { raw.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) } }
            finally { bitmap.recycle() }
            val cache = PhotoCache(context)
            val kept = cache.keep(PhotoImage.sanitize(raw))
            val id = kept.getString("photo_id")
            assertTrue(PhotoPolicy.validId(id))
            assertFalse(kept.has("jpeg_base64"))
            assertFalse(kept.getBoolean("uploaded"))
            val read = cache.read(id)
            assertEquals(kept.getString("sha256"), read.getString("sha256"))
            assertTrue(read.getString("jpeg_base64").isNotEmpty())
            try { cache.read("../synthetic-small"); fail("Traversal must be rejected") } catch (_: IllegalArgumentException) { }
            assertTrue(raw.exists())
            assertTrue(cache.discard(id))
            assertEquals(kept.getString("sha256"), cache.read(id).getString("sha256"))
            assertTrue(cache.clearAll())
            try { cache.read(id); fail("Explicitly erased photo must not be readable") } catch (_: Exception) { }
        }
    }

    @Test fun expiredLegacyOriginalMigratesUnchangedAndSurvivesSelectionCleanup() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = folder
                override fun getNoBackupFilesDir() = File(folder, "durable").apply { mkdirs() }
            }
            val bitmap = Bitmap.createBitmap(40, 30, Bitmap.Config.ARGB_8888)
            val stream = ByteArrayOutputStream()
            try { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)) }
            finally { bitmap.recycle() }
            val jpeg = requireNotNull(PhotoPolicy.stripEncoderMetadata(stream.toByteArray()))
            val legacy = File(folder, "after-you-photo-kept").apply { check(mkdir()) }
            val id = "1234567890abcdef1234567890abcdef"
            val source = File(legacy, "$id.jpg").apply { writeBytes(jpeg); check(setLastModified(1)) }
            val unrelated = File(folder, "unrelated-cache").apply { writeText("kept") }
            PhotoCache(context).migrateAvailable()
            assertFalse(source.exists())
            val cache = PhotoCache(context) // Actual reopened instance; no registration retained in RAM.
            assertArrayEquals(jpeg, android.util.Base64.decode(cache.read(id).getString("jpeg_base64"), android.util.Base64.DEFAULT))
            assertTrue(cache.discard(id))
            assertArrayEquals(jpeg, android.util.Base64.decode(PhotoCache(context).read(id).getString("jpeg_base64"), android.util.Base64.DEFAULT))
            // The old16-photo cache cap no longer limits a durable local library.
            val ids = (0 until 20).map { cache.keep(EncodedPhoto(jpeg, 40, 30)).getString("photo_id") }
            ids.forEach { assertEquals(jpeg.size, PhotoCache(context).read(it).getInt("byte_count")) }
            val durable = File(context.noBackupFilesDir, "after-you-photo-kept")
            assertEquals(1, requireNotNull(durable.listFiles()).count { it.name.endsWith(".jpg") })
            assertEquals("kept", unrelated.readText())
            assertTrue(cache.clearAll())
            assertTrue(requireNotNull(durable.listFiles()).isEmpty())
            assertEquals("kept", unrelated.readText())
        }
    }

    @Test fun approvedPlatformDirectoryAliasesResolveBeforeOwnedChildren() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = File(folder, "platform/../cache").apply { mkdirs() }
                override fun getNoBackupFilesDir() = File(folder, "platform/../durable").apply { mkdirs() }
            }
            File(folder, "platform").mkdirs()
            val jpeg = smallSafeJpeg()
            val kept = PhotoCache(context).keep(EncodedPhoto(jpeg, 40, 30))
            val read = PhotoCache(context).read(kept.getString("photo_id"))
            assertArrayEquals(jpeg, android.util.Base64.decode(read.getString("jpeg_base64"), android.util.Base64.DEFAULT))
            val root = File(context.noBackupFilesDir.canonicalFile, "after-you-photo-kept")
            assertEquals(root.absoluteFile, root.canonicalFile)
            assertTrue(File(root, kept.getString("sha256") + ".jpg").isFile)
        }
    }

    @Test fun unreadableLegacyPhotoDoesNotBlockDurableReadsOrOtherMigration() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = folder
                override fun getNoBackupFilesDir() = File(folder, "durable").apply { mkdirs() }
            }
            val jpeg = smallSafeJpeg()
            val cache = PhotoCache(context)
            val kept = cache.keep(EncodedPhoto(jpeg, 40, 30))
            val legacy = File(folder, "after-you-photo-kept").apply { check(mkdir()) }
            val blockedId = "a".repeat(32)
            val healthyId = "b".repeat(32)
            val blocked = File(legacy, "$blockedId.jpg").apply { writeBytes(jpeg) }
            val healthy = File(legacy, "$healthyId.jpg").apply { writeBytes(jpeg) }
            android.system.Os.chmod(blocked.path, 0)
            try {
                cache.migrateAvailable()
                assertTrue("Unmigrated bytes must remain for retry", blocked.exists())
                assertFalse(healthy.exists())
                assertEquals(kept.getString("sha256"), cache.read(healthyId).getString("sha256"))
                assertEquals(kept.getString("sha256"), cache.read(kept.getString("photo_id")).getString("sha256"))
                assertEquals(kept.getString("sha256"), cache.keep(EncodedPhoto(jpeg, 40, 30)).getString("sha256"))
            } finally { android.system.Os.chmod(blocked.path, 0x180) }
            cache.migrateAvailable()
            assertFalse(blocked.exists())
            assertArrayEquals(jpeg, android.util.Base64.decode(cache.read(blockedId).getString("jpeg_base64"), android.util.Base64.DEFAULT))
        }
    }

    @Test fun ownedPhotoRootAndContentSymlinksRemainRejected() {
        withFolder { folder ->
            val context = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
                override fun getCacheDir() = folder
                override fun getNoBackupFilesDir() = File(folder, "durable").apply { mkdirs() }
            }
            val jpeg = smallSafeJpeg()
            val outside = File(folder.canonicalFile, "unrelated").apply { check(mkdir()) }
            val original = File(outside, "keep.jpg").apply { writeBytes(jpeg) }
            val root = File(context.noBackupFilesDir.canonicalFile, "after-you-photo-kept")
            android.system.Os.symlink(outside.path, root.path)
            try {
                try { PhotoCache(context).keep(EncodedPhoto(jpeg, 40, 30)); fail("A replaced photo root must be rejected") }
                catch (_: IllegalStateException) { }
                assertArrayEquals(jpeg, original.readBytes())
            } finally { check(root.delete()) }
            check(root.mkdir())
            val hash = java.security.MessageDigest.getInstance("SHA-256").digest(jpeg).joinToString("") { "%02x".format(it.toInt() and 255) }
            val link = File(root, "$hash.jpg")
            android.system.Os.symlink(original.path, link.path)
            try {
                try { PhotoCache(context).keep(EncodedPhoto(jpeg, 40, 30)); fail("A content-file symlink must be rejected") }
                catch (_: IllegalStateException) { }
                assertArrayEquals(jpeg, original.readBytes())
            } finally { check(link.delete()) }
        }
    }

    private fun smallSafeJpeg(): ByteArray {
        val bitmap = Bitmap.createBitmap(40, 30, Bitmap.Config.ARGB_8888)
        val stream = ByteArrayOutputStream()
        try { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)) }
        finally { bitmap.recycle() }
        return requireNotNull(PhotoPolicy.stripEncoderMetadata(stream.toByteArray()))
    }

    private fun withFolder(work: (File) -> Unit) {
        val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(context.cacheDir, "photo-synthetic-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        try { work(folder) } finally {
            // This UUID-owned test directory contains only the files this test created.
            check(folder.canonicalFile.parentFile == context.cacheDir.canonicalFile)
            folder.deleteRecursively()
        }
    }

    private fun noiseBitmap(width: Int, height: Int, initialSeed: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        var seed = initialSeed
        val row = IntArray(width)
        for (y in 0 until height) {
            for (x in row.indices) {
                seed = seed * 1664525 + 1013904223
                row[x] = Color.rgb(seed ushr 16 and 255, seed ushr 8 and 255, seed and 255)
            }
            bitmap.setPixels(row, 0, width, 0, y, width, 1)
        }
        return bitmap
    }

    private fun assertNearColor(message: String, expected: Int, actual: Int) {
        assertTrue(message, kotlin.math.abs(Color.red(expected) - Color.red(actual)) <= 60 &&
            kotlin.math.abs(Color.green(expected) - Color.green(actual)) <= 60 &&
            kotlin.math.abs(Color.blue(expected) - Color.blue(actual)) <= 60)
    }

    private fun headerMarkers(bytes: ByteArray): String {
        val result = mutableListOf<String>()
        var i = 2
        while (i + 3 < bytes.size && result.size < 24 && bytes[i].toInt() and 255 == 255) {
            val marker = bytes[i + 1].toInt() and 255
            val length = (bytes[i + 2].toInt() and 255) * 256 + (bytes[i + 3].toInt() and 255)
            result.add(marker.toString(16) + ":" + length)
            if (marker == 0xda || length < 2) break
            i += length + 2
        }
        return result.joinToString(",")
    }
}
