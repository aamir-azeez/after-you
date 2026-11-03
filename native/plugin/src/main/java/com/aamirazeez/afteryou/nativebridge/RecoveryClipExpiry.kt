package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import android.view.ViewTreeObserver
import java.io.File
import java.io.FileNotFoundException
import java.nio.ByteBuffer

/**
 * Takes the copied recovery details back off the clipboard: two minutes after the copy,
 * and right after a paste import. It clears only a clip that is still ours, so whatever
 * the player copied since stays. Android lets an app read the clipboard only while its
 * window has focus, so a check that finds the app in the background waits for the next
 * focus; the deadline is kept in a small file so process death cannot leave the clip there.
 * Every method runs on the UI thread.
 */
internal class RecoveryClipExpiry(context: Context) {
    private val state = AtomicFile(File(context.applicationContext.noBackupFilesDir, "after-you-recovery-clip"))
    private val handler = Handler(Looper.getMainLooper())
    private val timer = Runnable { check() }
    private var host: Activity? = null
    private var observer: ViewTreeObserver? = null
    private val focus = ViewTreeObserver.OnWindowFocusChangeListener { focused -> if (focused) check() }

    fun attach(activity: Activity) {
        detach()
        host = activity
        observer = activity.window?.decorView?.viewTreeObserver?.also { it.addOnWindowFocusChangeListener(focus) }
        schedule()
    }

    fun detach() {
        handler.removeCallbacks(timer)
        observer?.takeIf { it.isAlive }?.removeOnWindowFocusChangeListener(focus)
        observer = null
        host = null
    }

    fun copied() {
        write(System.currentTimeMillis() + RecoveryClipboard.LIFETIME_MS)
        schedule()
    }

    /** On the timer, pause, resume and focus: clears an expired clip when the clipboard can be read. */
    fun check() {
        val deadline = RecoveryClipPolicy.deadline(read(), System.currentTimeMillis())
        if (deadline == 0L) return
        if (!RecoveryClipPolicy.due(deadline, System.currentTimeMillis())) {
            schedule()
            return
        }
        if (sweep(null)) write(0L)
    }

    /** After a paste import: the clip is cleared now when it is ours or holds the imported code. */
    fun imported(code: String) {
        if (sweep(RecoveryClipPolicy.importedCode(code))) write(0L)
    }

    /** True once the clipboard was read (and cleared when ours); false when it cannot be read yet. */
    private fun sweep(importedCode: String?): Boolean {
        val activity = host ?: return false
        if (!activity.hasWindowFocus()) return false
        val clipboard = activity.getSystemService(ClipboardManager::class.java) ?: return false
        val description = clipboard.primaryClipDescription ?: return true // Nothing on the clipboard.
        var text: CharSequence? = null
        // Reading the text shows Android's "pasted" note, so only for an import, which just pasted it.
        if (importedCode != null && description.label?.toString() != RecoveryClipboard.LABEL &&
            description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)) {
            text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text
        }
        if (RecoveryClipPolicy.ours(description.label, text, importedCode)) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) clipboard.clearPrimaryClip()
            else clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
        return true
    }

    private fun schedule() {
        handler.removeCallbacks(timer)
        val deadline = RecoveryClipPolicy.deadline(read(), System.currentTimeMillis())
        if (deadline > 0L) handler.postDelayed(timer, maxOf(0L, deadline - System.currentTimeMillis()))
    }

    private fun read(): Long = try {
        val bytes = state.readFully()
        if (bytes.size == 8) ByteBuffer.wrap(bytes).long else 0L
    } catch (_: FileNotFoundException) { 0L } catch (_: Exception) { 0L }

    private fun write(deadline: Long) {
        try {
            if (deadline <= 0L) { state.delete(); return }
            val stream = state.startWrite()
            try {
                stream.write(ByteBuffer.allocate(8).putLong(deadline).array())
                state.finishWrite(stream)
            } catch (e: Exception) {
                state.failWrite(stream)
                throw e
            }
        } catch (_: Exception) { }
    }
}
