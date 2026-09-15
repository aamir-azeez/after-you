package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Durable capture originals. Opaque legacy IDs remain aliases to immutable content hashes. */
internal class PhotoCache(private val context: Context) {
    private val root = File(context.noBackupFilesDir, "after-you-photo-kept")
    private val legacy = File(context.cacheDir, "after-you-photo-kept")

    @Synchronized fun migrateAvailable() = prepare()

    @Synchronized fun keep(photo: EncodedPhoto): JSONObject {
        require(PhotoPolicy.safeJpeg(photo.jpeg))
        prepare()
        val id = UUID.randomUUID().toString().replace("-", "")
        return store(id, photo.jpeg)
    }

    @Synchronized fun read(id: String): JSONObject {
        prepare()
        require(PhotoPolicy.validId(id))
        val alias = owned(root, "$id.json")
        val saved = readAlias(alias)
        val hash = saved.getString("sha256")
        require(Regex("[a-f0-9]{64}").matches(hash))
        val target = owned(root, "$hash.jpg")
        require(target.isFile && target.length() in 1..PhotoPolicy.MAX_JPEG_BYTES.toLong())
        val data = target.readBytes()
        require(PhotoPolicy.safeJpeg(data))
        val actual = metadata(id, data)
        require(actual.toString() == saved.toString())
        return actual.put("jpeg_base64", Base64.encodeToString(data, Base64.NO_WRAP))
    }

    @Synchronized fun discard(id: String): Boolean {
        require(PhotoPolicy.validId(id))
        // Ordinary selection cleanup must not erase an original after sharing or unsharing.
        // Its UI reference is retired by the caller; explicit account deletion uses clearAll.
        return true
    }

    /** Explicit deletion only; includes orphan selections unknown to any caller's journal. */
    @Synchronized fun clearAll(): Boolean = PhotoCachePurge.clearKept(context)

    private fun prepare() {
        check(root.isDirectory || root.mkdirs())
        check(root.canonicalFile == root.absoluteFile)
        // Import all still-available old originals, even ones older than the previous TTL.
        // Never delete an old file before its immutable copy and alias pass readback.
        if (!legacy.exists()) return
        check(legacy.isDirectory && legacy.canonicalFile == legacy.absoluteFile)
        for (old in requireNotNull(legacy.listFiles())) {
            val id = old.name.removeSuffix(".jpg")
            if (!old.name.endsWith(".jpg") || !PhotoPolicy.validId(id) || !old.isFile || old.canonicalFile != old.absoluteFile) continue
            if (old.length() !in 1..PhotoPolicy.MAX_JPEG_BYTES.toLong()) continue
            val bytes = old.readBytes()
            if (!PhotoPolicy.safeJpeg(bytes)) continue // Preserve malformed legacy evidence too.
            try {
                store(id, bytes)
                old.delete() // A failed legacy removal is harmless and retried later.
            } catch (_: Exception) {
                // One unreadable original or full disk must not prevent reading an
                // already-migrated photo. Preserve this source for a later retry.
            }
        }
    }

    private fun owned(folder: File, name: String): File {
        val target = File(folder, name)
        check(target.canonicalFile == target.absoluteFile && target.canonicalFile.parentFile == folder.canonicalFile)
        return target
    }

    private fun store(id: String, data: ByteArray): JSONObject {
        val meta = metadata(id, data)
        val target = owned(root, meta.getString("sha256") + ".jpg")
        if (target.exists()) require(target.length() == data.size.toLong() && target.readBytes().contentEquals(data)) else atomicWrite(target, data)
        val alias = owned(root, "$id.json")
        if (alias.exists()) {
            require(readAlias(alias).toString() == meta.toString())
        } else atomicWrite(alias, meta.toString().toByteArray(Charsets.UTF_8))
        require(target.readBytes().contentEquals(data))
        require(AtomicFile(alias).openRead().use { it.readBytes() }.contentEquals(meta.toString().toByteArray(Charsets.UTF_8)))
        return meta
    }

    private fun readAlias(alias: File): JSONObject = AtomicFile(alias).openRead().use {
        require(it.channel.size() in 1..4096)
        JSONObject(it.readBytes().toString(Charsets.UTF_8))
    }

    private fun atomicWrite(target: File, bytes: ByteArray) {
        check(root.usableSpace >= bytes.size + 2L * 1024 * 1024)
        val atomic = AtomicFile(target)
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
            stream.fd.sync()
            atomic.finishWrite(stream)
        } catch (failure: Exception) {
            atomic.failWrite(stream)
            throw failure
        }
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
