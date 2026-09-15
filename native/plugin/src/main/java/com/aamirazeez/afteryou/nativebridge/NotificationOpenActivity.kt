package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Non-exported PendingIntent target. Godot has no plugin onNewIntent hook in this version. */
class NotificationOpenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val eventId = intent?.getStringExtra(NotificationDelivery.EVENT_EXTRA) ?: ""
            if (NotificationPolicy.validEventId(eventId)) {
                NotificationStore(applicationContext).use { it.markTapped(eventId) }
            }
            packageManager.getLaunchIntentForPackage(packageName)?.let {
                // Bring an existing game Activity forward without CLEAR_TOP destroying it.
                // The journal coordinator, not this Activity, decides when a queued route is safe.
                it.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                startActivity(it)
            }
        } catch (_: Exception) {
            // A missing/stale hint or unavailable launcher cannot authorize another route.
        } finally { finish() }
    }
}
