package com.aamirazeez.afteryou.nativebridge

import android.content.ClipData
import android.content.ClipDescription
import android.os.PersistableBundle

/** The writer runs on the Activity's UI thread. Neither clipboard reads nor secret logging are needed. */
internal object RecoveryClipboard {
    /** The clip's label; RecoveryClipExpiry clears only a clip that still carries it. */
    const val LABEL = "After You recovery details"
    /** As on iOS: the copied details leave the clipboard after two minutes. */
    const val LIFETIME_MS = 120_000L

    fun copy(playerId: String, recoveryCode: String, write: (ClipData) -> Unit): Boolean {
        val text = BridgePolicy.recoveryText(playerId, recoveryCode) ?: return false
        val clip = ClipData.newPlainText(LABEL, text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
        write(clip)
        return true
    }
}

/** When the copied recovery details come off the clipboard. Pure, so the JVM tests cover it. */
internal object RecoveryClipPolicy {
    private val CODE = Regex("[A-Za-z0-9_-]{43}")

    /** A stored deadline beyond one lifetime from now means the clock moved back; it is due one lifetime from now. */
    fun deadline(stored: Long, now: Long): Long =
        if (stored <= 0L) 0L else minOf(stored, now + RecoveryClipboard.LIFETIME_MS)

    fun due(deadline: Long, now: Long): Boolean = deadline > 0L && now >= deadline

    /** The imported code, when it has the recovery code's exact form; anything else matches by label only. */
    fun importedCode(code: String): String? = code.takeIf { CODE.matches(it) }

    /** The clip is ours: it carries our label, or (just after an import) its text holds the imported code. */
    fun ours(label: CharSequence?, text: CharSequence?, importedCode: String?): Boolean =
        label?.toString() == RecoveryClipboard.LABEL ||
            (importedCode != null && text != null && text.length <= 4096 && text.contains(importedCode))
}
