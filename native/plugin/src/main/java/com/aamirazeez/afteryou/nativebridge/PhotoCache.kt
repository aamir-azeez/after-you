package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID

/** Only opaque IDs resolve files; no caller-supplied path is accepted or returned. */
internal class PhotoCache(private val context: Context) {
    private val root = File(context.cacheDir, "after-you-photo-kept")

    @Synchronized fun keep(photo: EncodedPhoto): JSONObject {
        require(PhotoPolicy.safeJpeg(photo.jpeg))
        prepare()
        check(ownedFiles().size < PhotoPolicy.MAX_FILES)
        val id = UUID.randomUUID().toString().replace("-", "")
        val target = file(id)
        try {
            FileOutputStream(target).use { it.write(photo.jpeg); it.fd.sync() }
            return metadata(id, photo.jpeg)
        } catch (failure: Exception) {
            target.delete()
            throw failure
        }
    }

    @Synchronized fun read(id: String): JSONObject {
        prepare()
        val target = file(id)
        require(target.isFile && target.length() in 1..PhotoPolicy.MAX_JPEG_BYTES.toLong())
        require(target.lastModified() >= System.currentTimeMillis() - PhotoPolicy.EXPIRY_MS)
        val data = target.readBytes()
        require(PhotoPolicy.safeJpeg(data))
        return metadata(id, data).put("jpeg_base64", Base64.encodeToString(data, Base64.NO_WRAP))
    }

    @Synchronized fun discard(id: String): Boolean {
        val target = file(id)
        return !target.exists() || target.delete()
    }

    /** Explicit deletion only; includes orphan selections unknown to any caller's journal. */
    @Synchronized fun clearAll(): Boolean = PhotoCachePurge.clearKept(context)

    private fun prepare() {
        check(root.isDirectory || root.mkdirs())
        val expired = System.currentTimeMillis() - PhotoPolicy.EXPIRY_MS
        ownedFiles().filter { it.lastModified() < expired }.forEach { it.delete() }
    }

    private fun ownedFiles() = root.listFiles()?.filter {
        it.isFile && it.name.endsWith(".jpg") && PhotoPolicy.validId(it.name.removeSuffix(".jpg"))
    }.orEmpty()

    private fun file(id: String): File {
        require(PhotoPolicy.validId(id))
        val target = File(root, "$id.jpg")
        check(target.canonicalFile.parentFile == root.canonicalFile)
        return target
    }

    private fun metadata(id: String, data: ByteArray): JSONObject {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        require(bounds.outWidth in 1..PhotoPolicy.MAX_EDGE && bounds.outHeight in 1..PhotoPolicy.MAX_EDGE)
        val hash = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it.toInt() and 255) }
        return JSONObject().put("status", "kept").put("photo_id", id).put("mime", "image/jpeg")
            .put("width", bounds.outWidth).put("height", bounds.outHeight).put("byte_count", data.size)
            .put("sha256", hash).put("metadata_removed", true).put("uploaded", false)
    }
}
