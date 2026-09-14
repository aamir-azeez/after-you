package com.aamirazeez.afteryou.nativebridge

import android.content.ClipData
import android.content.ClipDescription
import android.os.PersistableBundle

/** The writer runs on the Activity's UI thread. Neither clipboard reads nor secret logging are needed. */
internal object RecoveryClipboard {
    fun copy(playerId: String, recoveryCode: String, write: (ClipData) -> Unit): Boolean {
        val text = BridgePolicy.recoveryText(playerId, recoveryCode) ?: return false
        val clip = ClipData.newPlainText("After You recovery details", text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
        write(clip)
        return true
    }
}
