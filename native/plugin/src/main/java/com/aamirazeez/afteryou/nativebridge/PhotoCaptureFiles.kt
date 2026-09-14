package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/** Only the bridge's immediate UUID-named raw files; never kept photos or arbitrary cache entries. */
internal object PhotoCaptureFiles {
    private const val DIRECTORY = "after-you-photo-capture"

    fun directory(context: Context): File {
        val root = File(context.cacheDir.canonicalFile, DIRECTORY)
        check(root.canonicalFile == root)
        check(root.isDirectory || root.mkdirs())
        return root
    }

    /** Called on host creation and before a new flow, without opening the camera. */
    fun cleanupInterrupted(context: Context): Boolean = try {
        val root = directory(context)
        var clean = true
        for (file in requireNotNull(root.listFiles())) {
            if (!file.isFile || !file.name.endsWith(".jpg") || !PhotoPolicy.validId(file.name.removeSuffix(".jpg"))) continue
            // Do not follow a replaced file outside the exact bridge directory.
            if (file.canonicalFile.parentFile != root.canonicalFile) { clean = false; continue }
            try {
                val uri = FileProvider.getUriForFile(context, context.packageName + ".afteryou.photos", file)
                context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            } catch (_: Exception) { clean = false; continue }
            if (file.exists() && !file.delete()) clean = false
        }
        clean
    } catch (_: Exception) { false }
}
