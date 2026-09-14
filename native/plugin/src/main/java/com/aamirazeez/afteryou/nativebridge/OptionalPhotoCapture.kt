package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.widget.ImageView
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService

/** UI-only optional flow. No reference to a room, turn, network client, account or purchase exists. */
internal class OptionalPhotoCapture(
    private val activity: Activity,
    private val worker: ExecutorService,
    private val cache: PhotoCache,
    private val result: (String, JSONObject) -> Unit,
    private val error: (String, String) -> Unit
) {
    private val generations = PhotoCaptureGeneration(PhotoCameraRequestCodes(activity)::reserve)
    private var closed = false
    private var dialog: AlertDialog? = null
    private var raw: File? = null
    private var outputUri: Uri? = null
    private var previewBitmap: Bitmap? = null
    private var previewImage: ImageView? = null

    fun begin(id: String) {
        if (closed || activity.isFinishing || activity.isDestroyed) { error(id, "activity_unavailable"); return }
        if (generations.active == null && !PhotoCaptureFiles.cleanupInterrupted(activity)) {
            error(id, "photo_cleanup_unavailable"); return
        }
        val ticket = generations.begin(id) ?: run { error(id, "photo_busy"); return }
        try {
            dialog = AlertDialog.Builder(activity)
                .setTitle("Add a photo? It’s optional.")
                .setMessage("Your turn is already safe. Open the camera and choose the selfie lens if you like. You can preview, retake or skip. Nothing is uploaded by this photo tool.")
                .setPositiveButton("Open camera") { _, _ -> launchCamera(ticket) }
                .setNegativeButton("Skip") { _, _ -> skip(ticket) }
                .setOnCancelListener { skip(ticket) }
                .show()
        } catch (_: Exception) { fail(ticket, "photo_ui_unavailable") }
    }

    /** Called only from the explicit Open camera or Retake button. */
    private fun launchCamera(ticket: PhotoCaptureGeneration.Ticket) {
        if (!generations.isCurrent(ticket)) return
        clearPreview()
        cleanupRaw()
        try {
            check(PhotoCaptureFiles.cleanupInterrupted(activity))
            val folder = PhotoCaptureFiles.directory(activity)
            raw = File(folder, UUID.randomUUID().toString().replace("-", "") + ".jpg").apply { check(createNewFile()) }
            outputUri = FileProvider.getUriForFile(activity, activity.packageName + ".afteryou.photos", requireNotNull(raw))
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, outputUri)
                clipData = ClipData.newRawUri("Optional After You photo", outputUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            activity.startActivityForResult(intent, generations.cameraRequest(ticket))
        } catch (_: ActivityNotFoundException) { fail(ticket, "camera_unavailable")
        } catch (_: Exception) { fail(ticket, "camera_unavailable") }
    }

    fun onActivityResult(code: Int, resultCode: Int) {
        val ticket = generations.consumeCameraResult(code) ?: return
        if (resultCode != Activity.RESULT_OK) { skip(ticket); return }
        val source = raw ?: run { fail(ticket, "photo_missing"); return }
        if (!revokeGrant()) { fail(ticket, "photo_cleanup_unavailable"); return }
        try {
            worker.execute {
                var encoded = try { PhotoImage.sanitize(source) } catch (_: Exception) { null
                } catch (_: OutOfMemoryError) { null
                }
                val removed = !source.exists() || source.delete()
                if (!removed) encoded = null
                val prepared = encoded
                activity.runOnUiThread {
                    if (!generations.isCurrent(ticket)) return@runOnUiThread
                    if (removed) raw = null
                    if (prepared == null) fail(ticket, "photo_could_not_prepare") else showPreview(ticket, prepared)
                }
            }
        } catch (_: Exception) { fail(ticket, "photo_could_not_prepare") }
    }

    private fun showPreview(ticket: PhotoCaptureGeneration.Ticket, photo: EncodedPhoto) {
        if (!generations.isCurrent(ticket) || activity.isFinishing || activity.isDestroyed) { skip(ticket); return }
        try {
            val bitmap = requireNotNull(BitmapFactory.decodeByteArray(photo.jpeg, 0, photo.jpeg.size))
            previewBitmap = bitmap
            val view = ImageView(activity).apply {
                setImageBitmap(bitmap)
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
                val padding = (16 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding, padding, padding)
                maxHeight = (resources.displayMetrics.heightPixels * 0.48).toInt()
                contentDescription = "Preview of your optional photo"
            }
            previewImage = view
            dialog = AlertDialog.Builder(activity)
                .setTitle("Keep this photo?")
                .setMessage("Location and camera metadata have been removed. Keeping this local photo does not upload it.")
                .setView(view)
                .setPositiveButton("Use photo") { _, _ ->
                    if (generations.isCurrent(ticket)) {
                        try { finish(ticket, cache.keep(photo)) } catch (_: Exception) { fail(ticket, "photo_could_not_keep") }
                    }
                }
                .setNeutralButton("Retake") { _, _ -> launchCamera(ticket) }
                .setNegativeButton("Skip") { _, _ -> skip(ticket) }
                .setOnCancelListener { skip(ticket) }
                .show()
        } catch (_: Exception) { fail(ticket, "photo_preview_unavailable")
        } catch (_: OutOfMemoryError) { fail(ticket, "photo_preview_unavailable") }
    }

    fun cancel(id: String): Boolean {
        val ticket = generations.active?.takeIf { it.requestId == id } ?: return false
        generations.cameraCode(ticket)?.let { code ->
            try { activity.finishActivity(code) } catch (_: Exception) { }
        }
        skip(ticket)
        return true
    }

    fun close() {
        if (closed) return
        closed = true
        try { generations.active?.let { cancel(it.requestId) } } finally { clear() }
    }

    private fun skip(ticket: PhotoCaptureGeneration.Ticket) = finish(ticket, JSONObject().put("status", "skipped").put("uploaded", false))

    private fun finish(ticket: PhotoCaptureGeneration.Ticket, payload: JSONObject) {
        if (!generations.finish(ticket)) return
        clear()
        result(ticket.requestId, payload)
    }

    private fun fail(ticket: PhotoCaptureGeneration.Ticket, code: String) {
        if (!generations.finish(ticket)) return
        clear()
        error(ticket.requestId, code)
    }

    private fun clear() {
        try {
            dialog?.setOnCancelListener(null)
            dialog?.dismiss()
        } catch (_: Exception) { /* A destroyed window must not prevent file/grant cleanup. */ }
        finally {
            dialog = null
            clearPreview()
            cleanupRaw()
        }
    }

    private fun clearPreview() {
        previewImage?.setImageDrawable(null)
        previewImage = null
        previewBitmap?.recycle()
        previewBitmap = null
    }

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
