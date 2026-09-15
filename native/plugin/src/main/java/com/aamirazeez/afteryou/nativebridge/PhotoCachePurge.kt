package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import java.io.Closeable
import java.io.File
import java.nio.file.Files
import java.util.concurrent.ExecutorService

/** Explicit account-deletion cleanup only. Fixed photo roots; no caller-supplied path or identity. */
internal object PhotoCachePurge {
    fun clearRaw(context: Context): Boolean = clear(context, "after-you-photo-capture", true)
    fun clearKept(context: Context): Boolean {
        val legacy = clear(context, "after-you-photo-kept", false)
        val durable = clear(context, "after-you-photo-kept", false, true)
        return legacy && durable
    }

    /** UI caller closes capture; FIFO drains older work before the final cleanup acknowledgement. */
    fun afterCapture(context: Context, cache: PhotoCache, worker: ExecutorService, closeCapture: () -> Unit, done: (Boolean) -> Unit) {
        try {
            closeCapture()
            worker.execute {
                val cleared = try {
                    val rawCleared = clearRaw(context)
                    val keptCleared = cache.clearAll()
                    rawCleared && keptCleared
                } catch (_: Exception) { false }
                done(cleared)
            }
        } catch (_: Exception) { done(false) }
    }

    private fun clear(context: Context, name: String, revoke: Boolean, durable: Boolean = false): Boolean {
        return try {
            val root = File((if (durable) context.noBackupFilesDir else context.cacheDir).canonicalFile, name)
            check(root.canonicalFile == root) // A replaced/symlink root must not redirect deletion.
            if (!root.exists()) true else {
                check(root.isDirectory)
                var visited = 0
                var limitReached = false
                fun remove(file: File, depth: Int): Boolean {
                    if (visited >= 1024 || depth > 16) { limitReached = true; return false }
                    visited++
                    if (file.canonicalFile != file.absoluteFile ||
                        !file.canonicalPath.startsWith(root.path + File.separator)) return false
                    if (file.isDirectory) {
                        var clean = true
                        entries(file).use { children ->
                            while (children.hasNext()) {
                                if (visited >= 1024 || limitReached) { limitReached = true; clean = false; break }
                                if (!remove(children.next(), depth + 1)) clean = false
                            }
                        }
                        return clean && file.delete()
                    }
                    if (!file.isFile) return false
                    if (revoke) {
                        try {
                            val uri = FileProvider.getUriForFile(context, context.packageName + ".afteryou.photos", file)
                            context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        } catch (_: Exception) { return false } // Keep the name so a retry can revoke it.
                    }
                    return file.delete()
                }
                var clean = true
                entries(root).use { children ->
                    while (children.hasNext()) {
                        if (visited >= 1024 || limitReached) { clean = false; break }
                        if (!remove(children.next(), 1)) clean = false
                    }
                }
                clean && entries(root).use { !it.hasNext() }
            }
        } catch (_: Exception) { false }
    }

    private interface Entries : Closeable {
        fun hasNext(): Boolean
        fun next(): File
    }

    private fun entries(folder: File): Entries = if (Build.VERSION.SDK_INT >= 26) streamEntries(folder) else {
        // API24–25 lacks java.nio.file. Deletions are capped; this legacy name enumeration is bulk.
        val iterator = requireNotNull(folder.listFiles()).iterator()
        object : Entries {
            override fun hasNext() = iterator.hasNext()
            override fun next() = iterator.next()
            override fun close() = Unit
        }
    }

    @RequiresApi(26)
    private fun streamEntries(folder: File): Entries {
        val stream = Files.newDirectoryStream(folder.toPath())
        val iterator = stream.iterator()
        return object : Entries {
            override fun hasNext() = iterator.hasNext()
            override fun next() = iterator.next().toFile()
            override fun close() = stream.close()
        }
    }
}
