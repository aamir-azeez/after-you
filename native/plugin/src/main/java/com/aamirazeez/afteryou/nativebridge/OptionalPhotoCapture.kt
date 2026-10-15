package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService

/**
 * UI-only optional flow. No reference to a room, turn, network client, account or purchase exists.
 * The game's own card asks first, so the camera opens straight away and the kept photo goes back
 * to the game without another native dialog. The game shows the preview and the Send choice.
 */
internal class OptionalPhotoCapture(
    private val activity: Activity,
    private val worker: ExecutorService,
    private val recovery: PhotoCaptureRecovery,
    private val pending: PendingCaptureStore,
    private val result: (String, JSONObject) -> Unit,
    private val error: (String, String) -> Unit,
    reserveCode: () -> Int = PhotoCameraRequestCodes(activity)::reserve,
    private val finishSubActivity: (Int) -> Unit = { code -> activity.finishActivity(code) }
) {
    private val generations = PhotoCaptureGeneration(reserveCode)
    private var closed = false
    private var raw: File? = null
    private var outputUri: Uri? = null

    fun begin(id: String) {
        if (closed || activity.isFinishing || activity.isDestroyed) { error(id, "activity_unavailable"); return }
        if (generations.active == null && !PhotoCaptureFiles.cleanupInterrupted(activity)) {
            error(id, "photo_cleanup_unavailable"); return
        }
        val ticket = generations.begin(id) ?: run { error(id, "photo_busy"); return }
        launchCamera(ticket)
    }

    /** Called only from the game's explicit Take photo or retake button. */
    private fun launchCamera(ticket: PhotoCaptureGeneration.Ticket) {
        if (!generations.isCurrent(ticket)) return
        cleanupRaw()
        try {
            check(PhotoCaptureFiles.cleanupInterrupted(activity))
            val folder = PhotoCaptureFiles.directory(activity)
            val name = UUID.randomUUID().toString().replace("-", "") + ".jpg"
            raw = File(folder, name).apply { check(createNewFile()) }
            outputUri = FileProvider.getUriForFile(activity, activity.packageName + ".afteryou.photos", requireNotNull(raw))
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, outputUri)
                clipData = ClipData.newRawUri("Optional After You photo", outputUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            val code = generations.cameraRequest(ticket)
            // Durable before the camera opens: Android may destroy this Activity or process
            // while the camera is in front, and the photo must survive that.
            pending.write(PendingCapture(ticket.requestId, code, name, System.currentTimeMillis()))
            activity.startActivityForResult(intent, code)
        } catch (_: ActivityNotFoundException) { fail(ticket, "camera_unavailable")
        } catch (_: Exception) { fail(ticket, "camera_unavailable") }
    }

    fun handles(code: Int): Boolean = generations.active != null && generations.cameraCode(requireNotNull(generations.active)) == code

    fun onActivityResult(code: Int, resultCode: Int) {
        val ticket = generations.consumeCameraResult(code) ?: return
        val source = raw
        val size = if (source != null && source.isFile) source.length() else 0L
        when (PhotoCaptureRecoveryPolicy.live(size, resultCode)) {
            PhotoCaptureRecoveryPolicy.Live.SKIP -> skip(ticket)
            PhotoCaptureRecoveryPolicy.Live.FAIL -> fail(ticket, "photo_missing")
            PhotoCaptureRecoveryPolicy.Live.KEEP -> keep(ticket, requireNotNull(source))
        }
    }

    private fun keep(ticket: PhotoCaptureGeneration.Ticket, source: File) {
        if (!revokeGrant()) { fail(ticket, "photo_cleanup_unavailable"); return }
        try {
            worker.execute {
                val kept = recovery.adopt(source, ticket.requestId)
                val removed = !source.exists()
                activity.runOnUiThread {
                    if (!generations.isCurrent(ticket)) return@runOnUiThread
                    if (removed) raw = null
                    if (kept == null) fail(ticket, "photo_could_not_prepare") else finish(ticket, kept)
                }
            }
        } catch (_: Exception) { fail(ticket, "photo_could_not_prepare") }
    }

    /** An explicit cancel from the game. It never runs after Android destroyed the host. */
    fun cancel(id: String): Boolean {
        if (closed) return false
        val ticket = generations.active?.takeIf { it.requestId == id } ?: return false
        generations.cancelCode(ticket)?.let { code ->
            try { finishSubActivity(code) } catch (_: Exception) { }
        }
        skip(ticket)
        return true
    }

    /** Explicit account-deletion cleanup: closes the camera and removes every trace. */
    fun close() {
        if (closed) return
        try { generations.active?.let { cancel(it.requestId) } } finally {
            closed = true
            clear()
            try { pending.clear() } catch (_: Exception) { }
        }
    }

    /**
     * Android is destroying the host without the player asking. Leave the camera open and keep the
     * raw output, its grant and the pending record: the recreated Activity recovers the photo.
     */
    fun hostDestroyed() {
        if (closed) return
        closed = true
        generations.hostDestroyed()
    }

    private fun skip(ticket: PhotoCaptureGeneration.Ticket) = finish(ticket, JSONObject().put("status", "skipped").put("uploaded", false))

    private fun finish(ticket: PhotoCaptureGeneration.Ticket, payload: JSONObject) {
        if (!generations.finish(ticket)) return
        clear()
        try { pending.clear() } catch (_: Exception) { }
        result(ticket.requestId, payload)
    }

    private fun fail(ticket: PhotoCaptureGeneration.Ticket, code: String) {
        if (!generations.finish(ticket)) return
        clear()
        try { pending.clear() } catch (_: Exception) { }
        error(ticket.requestId, code)
    }

    private fun clear() = cleanupRaw()

    private fun revokeGrant(): Boolean {
        val uri = outputUri ?: return true
        return try {
            activity.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            outputUri = null
            true
        } catch (_: Exception) { false }
    }

    private fun cleanupRaw() {
        if (!revokeGrant()) return // Preserve the raw name for a later explicit cleanup retry.
        val source = raw
        if (source == null || !source.exists() || source.delete()) raw = null
    }
}

/** Dedicated non-exported provider: manifest exposes only the temporary camera-output directory. */
class AfterYouPhotoProvider : FileProvider()
