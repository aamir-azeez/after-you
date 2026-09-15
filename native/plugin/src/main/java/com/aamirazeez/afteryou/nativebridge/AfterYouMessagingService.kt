package com.aamirazeez.afteryou.nativebridge

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Runs without a Godot Activity. The server sends data-only, visible update hints. */
class AfterYouMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        if (!NotificationPolicy.validToken(token)) return
        try {
            NotificationStore(applicationContext).use { it.noteToken(token) }
            NotificationRuntime.tokenChanged()
        }
        catch (_: Exception) { /* Foreground get_token will retry without exposing the token. */ }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // The backend must never send an FCM notification block (which the SDK can auto-display).
        if (message.notification != null) return
        val event = NotificationPolicy.parse(message.data) ?: return
        try { NotificationDelivery.receive(applicationContext, event) }
        catch (_: Exception) { /* A push hint cannot change gameplay or crash the service. */ }
    }

    override fun onDeletedMessages() {
        // Reopening/focusing a room always fetches its authoritative state. No gameplay is
        // reconstructed from this callback or from the notification ledger.
    }
}
