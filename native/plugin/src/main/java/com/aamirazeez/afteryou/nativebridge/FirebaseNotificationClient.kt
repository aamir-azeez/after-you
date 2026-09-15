package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

/** Only Firebase's public Android resource configuration belongs in the APK. */
internal object NotificationConfiguration {
    fun valid(appId: String?, apiKey: String?, sender: String?, project: String?): Boolean =
        appId?.matches(Regex("1:[0-9]{6,20}:android:[A-Fa-f0-9]{16,64}")) == true &&
        apiKey?.matches(Regex("AIza[A-Za-z0-9_-]{35}")) == true &&
        sender?.matches(Regex("[0-9]{6,20}")) == true &&
        project?.matches(Regex("[a-z][a-z0-9-]{4,62}")) == true &&
        appId?.split(':')?.getOrNull(1) == sender
}

internal interface NotificationClient {
    val configured: Boolean
    fun autoInit(enabled: Boolean)
    fun token(done: (String?) -> Unit)
    fun deleteToken(done: (Boolean) -> Unit)
}

internal class FirebaseNotificationClient(private val context: Context) : NotificationClient {
    private fun options(): FirebaseOptions? = FirebaseOptions.fromResource(context)?.takeIf {
        NotificationConfiguration.valid(it.applicationId, it.apiKey, it.gcmSenderId, it.projectId)
    }
    override val configured: Boolean get() = try { options() != null } catch (_: Exception) { false }

    private fun messaging(): FirebaseMessaging {
        check(options() != null)
        // FirebaseInitProvider also uses these resources on a cold service launch. Manual
        // initialization here is only a fallback; auto-init is disabled in the manifest.
        FirebaseApp.initializeApp(context) ?: throw IllegalStateException("notification_unconfigured")
        return FirebaseMessaging.getInstance()
    }
    override fun autoInit(enabled: Boolean) { messaging().isAutoInitEnabled = enabled }
    override fun token(done: (String?) -> Unit) {
        messaging().token.addOnCompleteListener { task ->
            done(if (task.isSuccessful) task.result else null)
        }
    }
    override fun deleteToken(done: (Boolean) -> Unit) {
        messaging().deleteToken().addOnCompleteListener { done(it.isSuccessful) }
    }
}
