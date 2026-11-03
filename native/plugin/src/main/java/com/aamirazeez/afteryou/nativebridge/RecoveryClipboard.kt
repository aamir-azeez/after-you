package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.os.PersistableBundle

/**
 * The recovery details on the clipboard. A copy stays until the player replaces it (owner,
 * 2026-11-02: a timed clear would be annoying). Only a paste import takes it back off, right
 * after the details were used. Every method runs on the Activity's UI thread; nothing is logged.
 */
internal object RecoveryClipboard {
    /** The clip's label; the clear after an import knows our own copy by it. */
    const val LABEL = "After You recovery details"

    fun copy(playerId: String, recoveryCode: String, write: (ClipData) -> Unit): Boolean {
        val text = BridgePolicy.recoveryText(playerId, recoveryCode) ?: return false
        val clip = ClipData.newPlainText(LABEL, text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
        write(clip)
        return true
    }

    /**
     * After a paste import: clears the clip when it is ours or holds the imported code, and
     * leaves anything else. Android lets the app read the clipboard only while it has focus,
     * which it has right after the player pasted; without it nothing is touched.
     */
    fun clearImported(activity: Activity, recoveryCode: String) {
        if (!activity.hasWindowFocus()) return
        val clipboard = activity.getSystemService(ClipboardManager::class.java) ?: return
        val description = clipboard.primaryClipDescription ?: return
        val code = RecoveryClipPolicy.importedCode(recoveryCode)
        var text: CharSequence? = null
        // Reading the text shows Android's "pasted" note, so only when the label is not ours.
        if (code != null && description.label?.toString() != LABEL && description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)) {
            text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text
        }
        if (!RecoveryClipPolicy.ours(description.label, text, code)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) clipboard.clearPrimaryClip()
        else clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
    }
}

/** Which clip the clear after an import may take. Pure, so the JVM tests cover it. */
internal object RecoveryClipPolicy {
    private val CODE = Regex("[A-Za-z0-9_-]{43}")

    /** The imported code, when it has the recovery code's exact form; anything else matches by label only. */
    fun importedCode(code: String): String? = code.takeIf { CODE.matches(it) }

    /** The clip is ours: it carries our label, or its text holds the imported code. */
    fun ours(label: CharSequence?, text: CharSequence?, importedCode: String?): Boolean =
        label?.toString() == RecoveryClipboard.LABEL ||
            (importedCode != null && text != null && text.length <= 4096 && text.contains(importedCode))
}
