package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService

/**
 * Keeps a photo the player took even when the Activity or process that asked for it is gone.
 * Every kept photo is first marked as recovered; GDScript forgets the mark only after a turn
 * journal holds it, so a crash between the two never silently drops the picture.
 */
internal class PhotoCaptureRecovery(
    private val context: Context,
    private val cache: PhotoCache,
    private val pending: PendingCaptureStore,
    private val recovered: RecoveredPhotoStore,
    private val now: () -> Long = System::currentTimeMillis
) {
    /** Worker thread. Sanitize and keep, mark it recovered, then remove the raw output. */
    fun adopt(raw: File, requestId: String): JSONObject? {
        // The camera's write time is the capture time, also for a photo recovered after a restart.
        val takenAt = PhotoPolicy.takenAt(try { raw.lastModified() } catch (_: Exception) { 0L }, now())
        val metadata = try { cache.keep(PhotoImage.sanitize(raw), takenAt) } catch (_: Exception) { null
        } catch (_: OutOfMemoryError) { null
        }
        if (metadata != null) {
            try { recovered.write(RecoveredPhoto(requestId, metadata.toString())) } catch (_: Exception) { }
        }
        try { pending.clear() } catch (_: Exception) { }
        val removed = PhotoCaptureFiles.revoke(context, raw) && (!raw.exists() || raw.delete())
        if (!removed) {
            // The raw camera file keeps its metadata. Never report success while it remains.
            try { recovered.clear() } catch (_: Exception) { }
            return null
        }
        return metadata
    }

    /**
     * UI thread, at Activity start (resultCode null) or for a camera result that reached a
     * recreated Activity. Work that touches the photo runs on [worker], ahead of any new capture.
     */
    fun recover(worker: ExecutorService, resultCode: Int?) {
        val record = try { pending.read() } catch (_: Exception) { null }
        if (record == null) {
            if (resultCode == null) PhotoCaptureFiles.cleanupInterrupted(context)
            return
        }
        val raw = try { File(PhotoCaptureFiles.directory(context), record.rawName) } catch (_: Exception) { null }
        val exists = raw?.isFile == true
        val size = if (exists) requireNotNull(raw).length() else 0L
        when (PhotoCaptureRecoveryPolicy.decide(record, exists, size, now() - record.startedWallMs, resultCode)) {
            PhotoCaptureRecoveryPolicy.Decision.WAIT -> Unit
            PhotoCaptureRecoveryPolicy.Decision.DISCARD -> {
                try { pending.clear() } catch (_: Exception) { }
                PhotoCaptureFiles.cleanupInterrupted(context)
            }
            PhotoCaptureRecoveryPolicy.Decision.RECOVER -> worker.execute {
                adopt(requireNotNull(raw), record.requestId)
                PhotoCaptureFiles.cleanupInterrupted(context)
            }
        }
    }

    /** True when a camera result with this code belongs to the persisted request. */
    fun owns(requestCode: Int): Boolean = try { pending.read()?.requestCode == requestCode } catch (_: Exception) { false }

    /** Worker thread. The unadopted photo, without removing its mark. */
    fun peek(): JSONObject {
        val marker = try { recovered.read() } catch (_: Exception) { null }
        val photo = marker?.let { try { JSONObject(it.metadataJson) } catch (_: Exception) { null } }
        if (marker == null || photo == null) return JSONObject().put("recovered", false)
        return JSONObject().put("recovered", true).put("request_id", marker.requestId).put("photo", photo)
    }

    /** Worker thread. Removes the mark once a turn journal holds this exact photo. */
    fun forget(photoId: String): Boolean {
        val marker = try { recovered.read() } catch (_: Exception) { null } ?: return false
        val id = try { JSONObject(marker.metadataJson).optString("photo_id") } catch (_: Exception) { "" }
        if (id != photoId) return false
        recovered.clear()
        return true
    }

    /** Explicit account deletion only. */
    fun clearAll() {
        try { pending.clear() } catch (_: Exception) { }
        try { recovered.clear() } catch (_: Exception) { }
    }
}
