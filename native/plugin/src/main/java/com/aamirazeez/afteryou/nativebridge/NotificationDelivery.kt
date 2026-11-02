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
    const val HOSTING_CHANNEL = "after_you_friend_rooms_v1"
    const val POLLEN_CHANNEL = "after_you_pollen_v1"
    private fun categories(context: Context) = context.getSharedPreferences("after_you_notification_categories", Context.MODE_PRIVATE)
    fun setCategories(context: Context, turns: Boolean, hosting: Boolean, requests: Boolean) {
        check(categories(context).edit().putBoolean("turns", turns).putBoolean("hosting", hosting).putBoolean("requests", requests).commit())
    }
    fun categoryEnabled(context: Context, kind: String): Boolean = when (kind) {
        "friend_room_available" -> categories(context).getBoolean("hosting", false)
        "redo_requested" -> categories(context).getBoolean("requests", false)
        // Monthly Pollen rides the main notifications switch; Godot always saves it.
        NotificationPolicy.POLLEN_KIND -> categories(context).getBoolean("turns", false)
        else -> categories(context).getBoolean("turns", kind == "turn_ready")
    }
    const val EVENT_EXTRA = "after_you_event_id"
    private const val TAG_PREFIX = "after_you_update:"

    fun permissionGranted(context: Context): Boolean = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun enabled(context: Context): Boolean = permissionGranted(context) && NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(HOSTING_CHANNEL, "Friend rooms", NotificationManager.IMPORTANCE_DEFAULT).apply {
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        })
        manager.createNotificationChannel(NotificationChannel(TURN_CHANNEL, "Friend turns", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = PlayerCopy.NOTIFICATIONDELIVERY_04C4F3638050
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        })
        manager.createNotificationChannel(NotificationChannel(POLLEN_CHANNEL, PlayerCopy.NOTIFICATIONDELIVERY_POLLEN_CHANNEL, NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = PlayerCopy.NOTIFICATIONDELIVERY_POLLEN_CHANNEL_DESCRIPTION
            lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
        })
    }

    fun channelFor(kind: String): String = when (kind) {
        "friend_room_available" -> HOSTING_CHANNEL
        NotificationPolicy.POLLEN_KIND -> POLLEN_CHANNEL
        else -> TURN_CHANNEL
    }

    /** One visible notification per room and kind, and one for monthly Pollen: a newer hint replaces the older one. */
    fun tag(event: TurnNotification): String =
        TAG_PREFIX + NotificationStore.hash(if (event.isPollen) event.kind else event.family + ":" + event.roomId + ":" + event.kind)

    fun channelEnabled(context: Context, channel: String): Boolean = enabled(context) &&
        (Build.VERSION.SDK_INT < 26 || context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE)

    /** Database and notification posting share the same lock as opt-out/account rebinding. */
    fun receive(context: Context, event: TurnNotification) = synchronized(NotificationGuard.lock) {
        if (!categoryEnabled(context, event.kind)) return@synchronized
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
        if (!categoryEnabled(context, event.kind)) return
        if (NotificationRuntime.foreground(event)) return
        if (!enabled(context)) return
        createChannels(context)
        val channel = channelFor(event.kind)
        if (!channelEnabled(context, channel)) return
        val intent = Intent(context, NotificationOpenActivity::class.java).apply {
            // A fixed explicit target; no supplied URL, component or activity flags are accepted.
            action = context.packageName + ".OPEN_UPDATE." + event.eventId
            putExtra(EVENT_EXTRA, event.eventId)
        }
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val publicView = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.after_you_notification)
            .setContentTitle("After You")
            .setContentText(if (event.isPollen) PlayerCopy.NOTIFICATIONDELIVERY_POLLEN_TITLE else PlayerCopy.NOTIFICATIONDELIVERY_A5B249A65E48).build()
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.after_you_notification)
            .setContentTitle(when (event.kind) {
                "friend_room_available" -> "Friend rooms"
                "redo_requested" -> PlayerCopy.NOTIFICATIONDELIVERY_REDO_REQUESTED
                NotificationPolicy.POLLEN_KIND -> PlayerCopy.NOTIFICATIONDELIVERY_POLLEN_TITLE
                else -> "Your friend left a turn"
            })
            .setContentText(if (event.isPollen) PlayerCopy.pollenBody(event.amount) else PlayerCopy.NOTIFICATIONDELIVERY_D4901221095C)
            .setCategory(if (event.isPollen) null else NotificationCompat.CATEGORY_SOCIAL)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPublicVersion(publicView)
            .setOnlyAlertOnce(true).setAutoCancel(true).setContentIntent(pending)
            .setTimeoutAfter(NotificationPolicy.RETENTION_MS)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(tag(event), 1, notification)
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
