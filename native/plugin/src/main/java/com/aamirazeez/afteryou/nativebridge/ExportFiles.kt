package com.aamirazeez.afteryou.nativebridge

import java.io.File

/**
 * The one file a share sheet is handed (Export this run): written under the cache's export
 * folder, which after_you_photo_paths.xml lists for the FileProvider, so a read grant can reach
 * it. Only the newest export is kept; the folder holds nothing else, and the system may clear it.
 */
object ExportFiles {
    /** The cache folder after_you_photo_paths.xml names as "exports". */
    const val DIRECTORY = "after-you-exports"
    const val MAX_NAME = 96
    const val DEFAULT_MIME = "application/octet-stream"
    private val MIME = Regex("^[a-z]+/[a-z0-9.+-]{1,64}$")

    /** A plain lowercase file name (letters, digits, dot, dash, underscore), or null. */
    fun safeName(name: String): String? {
        val cleaned = name.trim().lowercase().replace(Regex("[^a-z0-9._-]+"), "-").replace(Regex("-{2,}"), "-").trim('-', '.')
        return if (cleaned.isEmpty() || cleaned.length > MAX_NAME) null else cleaned
    }

    fun mimeType(value: String): String = if (MIME.matches(value)) value else DEFAULT_MIME

    /** Writes `bytes` as the export folder's only file; null when the name, the size or the write fails. */
    fun write(cacheDir: File, name: String, bytes: ByteArray): File? {
        val safe = safeName(name) ?: return null
        if (bytes.isEmpty()) return null
        val folder = File(cacheDir, DIRECTORY)
        val target = File(folder, safe)
        if (!HistoryFiles.write(target, bytes)) return null
        folder.listFiles()?.forEach { if (it.name != safe) it.delete() }
        return target
    }
}
