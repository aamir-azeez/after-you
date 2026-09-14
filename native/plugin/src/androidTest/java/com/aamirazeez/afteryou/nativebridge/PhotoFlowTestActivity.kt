package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Executors
import java.lang.ref.WeakReference

/** Manual camera harness in the separate test APK. No game, credential or network access. */
class PhotoFlowTestActivity : Activity() {
    companion object { internal var current = WeakReference<PhotoFlowTestActivity>(null) }
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var cache: PhotoCache
    private lateinit var capture: OptionalPhotoCapture
    private lateinit var status: TextView
    private var requestCount = 0
    private var activeId: String? = null
    private var keptId: String? = null
    private var clearing = false
    private var callbacks = 0
    private var duplicateCallbacks = 0
    private val completed = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        audit("created")
        val interruptedOutputClean = PhotoCaptureFiles.cleanupInterrupted(this)
        cache = PhotoCache(this)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val inset = (24 * resources.displayMetrics.density).toInt()
            setPadding(inset, inset, inset, inset)
        }
        status = TextView(this).apply {
            textSize = 18f
            text = "Test APK only; explicit Capture required. startup_cleanup=" + interruptedOutputClean + "; " + auditSummary()
        }
        column.addView(status)
        capture = newCapture()
        button(column, "Capture optional photo") { beginCapture(false) }
        button(column, "Capture; cancel automatically in 8 seconds") { beginCapture(true) }
        button(column, "Cancel current capture") {
            val cancelled = activeId?.let { capture.cancel(it) } ?: false
            report("cancelled=" + cancelled + "; callbacks=" + callbacks + "; duplicates=" + duplicateCallbacks)
        }
        button(column, "Check kept photo locally") {
            val id = keptId
            if (id == null) report("No kept photo in this test activity.") else try {
                val value = cache.read(id)
                val bytes = Base64.decode(value.getString("jpeg_base64"), Base64.NO_WRAP)
                report("read_ok=true; size_ok=" + (bytes.size <= PhotoPolicy.MAX_JPEG_BYTES) +
                    "; shape_ok=" + (value.getInt("width") in 1..960 && value.getInt("height") in 1..960) +
                    "; jpeg_policy_ok=" + PhotoPolicy.safeJpeg(bytes) + "; uploaded=" + value.optBoolean("uploaded"))
            } catch (_: Exception) { report("read_ok=false") }
        }
        button(column, "Discard kept photo") {
            val id = keptId
            val removed = id?.let { cache.discard(it) } ?: false
            if (removed) keptId = null
            report("discarded=" + removed)
        }
        button(column, "Recreate test activity") { recreate() }
        button(column, "Clear all local test photos") { requestTestClear() }
        setContentView(column)
    }

    private fun newCapture() = OptionalPhotoCapture(this, worker, cache, { id, payload ->
        noteCallback(id)
        audit(if (payload.optString("status") == "kept") "kept" else "skipped")
        if (payload.optString("status") == "kept") keptId = payload.getString("photo_id")
        report("result=" + payload.optString("status") + "; uploaded=" + payload.optBoolean("uploaded") +
            "; payload_has_pixels=" + payload.has("jpeg_base64") + "; callbacks=" + callbacks + "; duplicates=" + duplicateCallbacks)
    }, { id, code ->
        noteCallback(id)
        audit("errors")
        report("error=" + code + "; callbacks=" + callbacks + "; duplicates=" + duplicateCallbacks)
    })

    internal fun requestTestClear() {
        if (clearing || isFinishing || isDestroyed) return
        clearing = true
        PhotoCachePurge.afterCapture(applicationContext, cache, worker, { capture.close() }) { cleared ->
            runOnUiThread {
                clearing = false
                if (isDestroyed) return@runOnUiThread
                capture = newCapture()
                if (cleared) keptId = null
                report("cleared=" + cleared + "; callbacks=" + callbacks + "; duplicates=" + duplicateCallbacks)
            }
        }
    }

    private fun beginCapture(cancelLater: Boolean) {
        if (clearing) { report("clear_busy=true"); return }
        audit("explicit_capture")
        val id = "photo-ui-" + (++requestCount)
        activeId = id
        capture.begin(id)
        if (cancelLater) handler.postDelayed({ if (!isFinishing && !isDestroyed) capture.cancel(id) }, 8000)
    }

    private fun noteCallback(id: String) {
        callbacks++
        if (!completed.add(id)) duplicateCallbacks++
        if (activeId == id) activeId = null
    }

    private fun report(value: String) { if (!isDestroyed) status.text = value }

    /** Called only by the disposable test APK's explicit ADB receiver, including behind the camera. */
    internal fun requestTestRecreation() {
        if (isFinishing || isDestroyed) return
        audit("recreate_requested")
        handler.post { if (!isFinishing && !isDestroyed) recreate() }
    }

    private fun audit(event: String) {
        val values = getSharedPreferences("photo-flow-lifecycle-test", MODE_PRIVATE)
        check(values.edit().putInt(event, values.getInt(event, 0) + 1).commit())
    }

    private fun auditSummary(): String {
        val values = getSharedPreferences("photo-flow-lifecycle-test", MODE_PRIVATE)
        return listOf("created", "destroyed", "recreate_requested", "explicit_capture", "kept", "skipped", "errors", "camera_results")
            .joinToString("; ") { it + "=" + values.getInt(it, 0) }
    }

    private fun button(column: LinearLayout, label: String, action: () -> Unit) {
        column.addView(Button(this).apply { text = label; setOnClickListener { action() } })
    }

    @Deprecated("The production camera bridge uses Activity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        audit("camera_results")
        capture.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (::capture.isInitialized) capture.close()
        audit("destroyed")
        if (current.get() === this) current.clear()
        worker.shutdown()
        super.onDestroy()
    }
}
