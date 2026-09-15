package com.aamirazeez.afteryou.nativebridge

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

internal object NotificationDelivery {
    const val TURN_CHANNEL = "after_you_turns_v1"
    const val EVENT_EXTRA = "after_you_event_id"
    private const val TAG_PREFIX = "after_you_update:"

    fun permissionGranted(context: Context): Boolean = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun enabled(context: Context): Boolean = permissionGranted(context) && NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(TURN_CHANNEL, "Friend turns", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "When your friend leaves a turn for you."
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        })

    }

    fun channelEnabled(context: Context, channel: String): Boolean = enabled(context) &&
        (Build.VERSION.SDK_INT < 26 || context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE)

    /** Database and notification posting share the same lock as opt-out/account rebinding. */
    fun receive(context: Context, event: TurnNotification) = synchronized(NotificationGuard.lock) {
        NotificationStore(context).use { store ->
            if (store.receive(event, System.currentTimeMillis())) deliver(context, store, event)
        }
    }

    fun retryPending(context: Context) = synchronized(NotificationGuard.lock) {
        NotificationStore(context).use { store ->
            for (event in store.pendingPosts(System.currentTimeMillis())) deliver(context, store, event)
        }
    }

    private fun deliver(context: Context, store: NotificationStore, event: TurnNotification) {
        if (NotificationRuntime.foreground(event)) return
        if (!enabled(context)) return
        createChannels(context)
        val channel = TURN_CHANNEL
        if (!channelEnabled(context, channel)) return
        val intent = Intent(context, NotificationOpenActivity::class.java).apply {
            // A fixed explicit target; no supplied URL, component or activity flags are accepted.
            action = context.packageName + ".OPEN_UPDATE." + event.eventId
            putExtra(EVENT_EXTRA, event.eventId)
        }
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val publicView = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.after_you_notification)
            .setContentTitle("After You").setContentText("A shared moment has an update.").build()
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.after_you_notification)
            .setContentTitle("Your friend left a turn")
            .setContentText("Open After You to see your shared moment.")
            .setCategory(NotificationCompat.CATEGORY_SOCIAL)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPublicVersion(publicView)
            .setOnlyAlertOnce(true).setAutoCancel(true).setContentIntent(pending)
            .setTimeoutAfter(NotificationPolicy.RETENTION_MS)
            .build()
        try {
            val tag = TAG_PREFIX + NotificationStore.hash(event.family + ":" + event.roomId + ":" + event.kind)
            NotificationManagerCompat.from(context).notify(tag, 1, notification)
            store.markPosted(event)
        } catch (_: SecurityException) {
            // Permission can change after the check. Keep the event pending, without logging it.
        }
    }

    fun cancelVisible(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        for (notification in manager.activeNotifications) {
            if (notification.tag?.startsWith(TAG_PREFIX) == true) manager.cancel(notification.tag, notification.id)
        }
    }
}
