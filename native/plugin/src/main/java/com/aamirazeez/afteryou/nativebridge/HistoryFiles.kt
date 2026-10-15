package com.aamirazeez.afteryou.nativebridge

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Durable file writes for room attempts the server may delete once this phone
 * has confirmed them. The bytes go to a sibling temporary file, which is synced
 * to storage before it is renamed over the target, so after a true return a
 * power cut leaves either the old file or the new one, never a torn one.
 */
object HistoryFiles {
    const val MAX_BYTES = 8 * 1024 * 1024

    /** Only files inside the app's own files directory, never through `..` or links out of it. */
    fun allowed(root: File, target: File): Boolean = try {
        target.canonicalPath.startsWith(root.canonicalPath + File.separator)
    } catch (_: IOException) {
        false
    }

    /** Atomic rename over the target: java.nio where Android has it (API 26+), else rename(2), which replaces on Linux. */
    private fun replace(source: File, target: File): Boolean = try {
        java.nio.file.Files.move(source.toPath(), target.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        true
    } catch (_: LinkageError) {
        source.renameTo(target)
    } catch (_: IOException) {
        false
    }

    fun write(target: File, bytes: ByteArray): Boolean {
        if (bytes.size > MAX_BYTES) return false
        val parent = target.parentFile ?: return false
        if (!parent.isDirectory && !parent.mkdirs()) return false
        val temporary = File(parent, target.name + ".new")
        return try {
            FileOutputStream(temporary).use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            if (replace(temporary, target)) true else {
                temporary.delete()
                false
            }
        } catch (_: IOException) {
            temporary.delete()
            false
        }
    }
}
