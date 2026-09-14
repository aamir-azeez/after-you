package com.aamirazeez.afteryou.nativebridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Test APK only. Recreates an existing test Activity; cannot launch a capture or the game. */
class PhotoLifecycleControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.aamirazeez.afteryou.nativebridge.test.RECREATE_PHOTO_ACTIVITY") {
            PhotoFlowTestActivity.current.get()?.requestTestRecreation()
        } else if (intent.action == "com.aamirazeez.afteryou.nativebridge.test.CLEAR_PHOTOS") {
            PhotoFlowTestActivity.current.get()?.requestTestClear()
        }
    }
}
