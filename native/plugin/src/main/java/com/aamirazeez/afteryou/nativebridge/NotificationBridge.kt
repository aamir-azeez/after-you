package com.aamirazeez.afteryou.nativebridge

import android.Manifest
import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.lang.ref.WeakReference

internal interface NotificationHost {
    fun permissionGranted(): Boolean
    fun channelEnabled(): Boolean
    fun createChannels()
    fun requestPermission(requestCode: Int): Boolean
    fun cancelVisible()
}

internal class AndroidNotificationHost(activity: Activity) : NotificationHost {
    private val owner = WeakReference(activity)
    private val context = activity.applicationContext
    override fun permissionGranted() = NotificationDelivery.permissionGranted(context)
    override fun channelEnabled() = NotificationDelivery.channelEnabled(context, NotificationDelivery.TURN_CHANNEL)
    override fun createChannels() = NotificationDelivery.createChannels(context)
    override fun cancelVisible() = NotificationDelivery.cancelVisible(context)
    override fun requestPermission(requestCode: Int): Boolean {
        val activity = owner.get() ?: return false
        if (activity.isFinishing || activity.isDestroyed) return false
        if (Build.VERSION.SDK_INT >= 33) activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), requestCode)
        return true
    }
}

/** Local bridge only. Registration/authentication and navigation are owned by the Godot client. */
internal class NotificationBridge(
    private val context: Context,
    private val host: NotificationHost,
    private val client: NotificationClient,
    result: (String, String, String) -> Unit,
    error: (String, String, String) -> Unit,
    received: (String) -> Unit,
    tokenChanged: (String) -> Unit
) : NotificationObserver {
    companion object {
        const val PERMISSION_REQUEST = 53013
        const val LOCAL_TIMEOUT_MS = 9_000L
        const val PERMISSION_TIMEOUT_MS = 90_000L
    }
    private val handler = Handler(Looper.getMainLooper())
    private val requests = NotificationRequests()
    private val deadlines = mutableMapOf<NotificationRequests.Ticket, Runnable>()
    private var resultSink: ((String, String, String) -> Unit)? = result
    private var errorSink: ((String, String, String) -> Unit)? = error
    private var receivedSink: ((String) -> Unit)? = received
    private var tokenSink: ((String) -> Unit)? = tokenChanged
    private var permissionTicket: NotificationRequests.Ticket? = null
    private var sdkBusy = false
    @Volatile private var resumed = false
    @Volatile private var godotReady = false
    @Volatile private var closed = false

    init { NotificationRuntime.attach(this) }

    private fun state(): NotificationRegistration = NotificationStore(context).use { it.registration() }
    private fun statusJson(): JSONObject {
        val s = state()
        val configured = client.configured
        return JSONObject().put("supported", configured).put("configured", configured)
            .put("opted_in", s.optedIn).put("permission_granted", host.permissionGranted())
            .put("channel_enabled", host.channelEnabled()).put("registration_pending", s.pending)
            .put("generation", s.generation)
    }

    private fun call(id: String, operation: String, timeout: Long = LOCAL_TIMEOUT_MS, action: (NotificationRequests.Ticket) -> Unit) {
        handler.post {
            if (closed) return@post
            val ticket = requests.begin(id, operation) ?: return@post
            val deadline = Runnable { fail(ticket, "notification_timeout") }
            deadlines[ticket] = deadline
            handler.postDelayed(deadline, timeout)
            try { action(ticket) } catch (_: Exception) { fail(ticket, "notification_unavailable") }
        }
    }
    private fun finish(ticket: NotificationRequests.Ticket): Boolean {
        if (!requests.finish(ticket)) return false
        deadlines.remove(ticket)?.let { handler.removeCallbacks(it) }
        if (permissionTicket == ticket) permissionTicket = null
        return true
    }
    private fun success(ticket: NotificationRequests.Ticket, data: JSONObject) {
        if (finish(ticket)) resultSink?.invoke(ticket.id, ticket.operation, data.toString())
    }
    private fun fail(ticket: NotificationRequests.Ticket, code: String) {
        if (finish(ticket)) errorSink?.invoke(ticket.id, ticket.operation, code)
    }

    fun status(id: String) = call(id, "status") { success(it, statusJson()) }

    fun requestPermission(id: String) = call(id, "request_permission", PERMISSION_TIMEOUT_MS) { ticket ->
        if (!client.configured) { fail(ticket, "notification_unconfigured"); return@call }
        if (permissionTicket != null) { fail(ticket, "notification_permission_busy"); return@call }
        host.createChannels()
        permissionTicket = ticket
        if (host.permissionGranted()) completePermission(ticket)
        else if (!host.requestPermission(PERMISSION_REQUEST)) fail(ticket, "notification_activity_unavailable")
    }
    private fun completePermission(ticket: NotificationRequests.Ticket) {
        val granted = host.permissionGranted()
        NotificationStore(context).use { it.setOptedIn(granted) }
        if (!granted) host.cancelVisible()
        if (!granted) client.autoInit(false)
        success(ticket, statusJson())
    }
    fun permissionResult(requestCode: Int, permissions: Array<out String>) {
        if (requestCode != PERMISSION_REQUEST || (permissions.isNotEmpty() && !permissions.contains(Manifest.permission.POST_NOTIFICATIONS))) return
        handler.post {
            val ticket = permissionTicket ?: return@post
            if (!requests.current(ticket) || closed) return@post
            try { completePermission(ticket) } catch (_: Exception) { fail(ticket, "notification_unavailable") }
        }
    }

    fun getToken(id: String) = call(id, "get_token") { ticket ->
        if (!client.configured) { fail(ticket, "notification_unconfigured"); return@call }
        if (sdkBusy) { fail(ticket, "notification_provider_busy"); return@call }
        val before = state()
        if (!before.optedIn || !host.permissionGranted()) { fail(ticket, "notification_not_enabled"); return@call }
        client.autoInit(true)
        sdkBusy = true
        try { client.token { token -> handler.post {
            sdkBusy = false
            if (closed || !requests.current(ticket)) return@post
            try {
                synchronized(NotificationGuard.lock) {
                val current = state()
                if (!current.optedIn || current.generation != before.generation) {
                    fail(ticket, "notification_binding_changed"); return@post
                }
                if (token == null || !NotificationPolicy.validToken(token)) {
                    fail(ticket, "notification_token_unavailable"); return@post
                }
                if (current.tokenHash != before.tokenHash && current.tokenHash != NotificationStore.hash(token)) {
                    fail(ticket, "notification_binding_changed"); return@post
                }
                NotificationStore(context).use { it.noteToken(token) }
                val next = state()
                success(ticket, JSONObject().put("token", token).put("generation", next.generation))
                }
            } catch (_: Exception) { fail(ticket, "notification_unavailable") }
        } } } catch (_: Exception) { sdkBusy = false; fail(ticket, "notification_token_unavailable") }
    }

    fun setBinding(epoch: String, token: String, generation: Long, id: String) = call(id, "set_binding") { ticket ->
        if (!client.configured || !host.permissionGranted()) { fail(ticket, "notification_not_enabled"); return@call }
        synchronized(NotificationGuard.lock) {
            val before = state()
            val bound = NotificationStore(context).use { it.bind(epoch, token, generation) }
            if (!bound) { fail(ticket, "notification_binding_changed"); return@synchronized }
            if (before.epoch != epoch) host.cancelVisible()
            success(ticket, JSONObject().put("bound", true).put("binding_epoch", epoch).put("generation", state().generation))
        }
    }

    fun clearBinding(id: String) = call(id, "clear_binding") { ticket ->
        synchronized(NotificationGuard.lock) {
            val next = NotificationStore(context).use { it.clearBinding() }
            host.cancelVisible()
            success(ticket, JSONObject().put("cleared", true).put("generation", next.generation))
        }
    }

    fun disable(id: String) = call(id, "disable") { ticket ->
        val next = synchronized(NotificationGuard.lock) {
            NotificationStore(context).use { it.setOptedIn(false) }.also { host.cancelVisible() }
        }
        fun done(deleted: Boolean) {
            success(ticket, JSONObject().put("disabled", true).put("token_deleted", deleted).put("generation", next.generation))
        }
        if (!client.configured) { done(next.tokenHash.isEmpty()); return@call }
        client.autoInit(false)
        if (sdkBusy) { fail(ticket, "notification_provider_busy"); return@call }
        sdkBusy = true
        try { client.deleteToken { deleted -> handler.post {
            sdkBusy = false
            if (closed || !requests.current(ticket)) return@post
            try {
                if (state().generation != next.generation) fail(ticket, "notification_binding_changed")
                else done(deleted)
            } catch (_: Exception) { fail(ticket, "notification_unavailable") }
        } } } catch (_: Exception) { sdkBusy = false; done(false) }
    }

    fun pendingRoute(id: String) = call(id, "pending_route") { ticket ->
        val route = NotificationStore(context).use { it.pendingRoute(System.currentTimeMillis()) }
        success(ticket, JSONObject().put("route", if (route == null) JSONObject() else JSONObject(route.fields())))
    }
    fun acknowledge(eventId: String, id: String) = call(id, "ack_route") { ticket ->
        val acknowledged = NotificationStore(context).use { it.acknowledge(eventId) }
        if (acknowledged) success(ticket, JSONObject().put("acknowledged", true).put("event_id", eventId))
        else fail(ticket, "notification_route_unavailable")
    }

    fun resume() { resumed = true; flush() }
    fun pause() { resumed = false }
    fun ready() { godotReady = true; flush() }
    private fun flush() { handler.post {
        if (closed || !resumed || !godotReady) return@post
        try { NotificationDelivery.retryPending(context) } catch (_: Exception) { /* Next foreground refresh remains authoritative. */ }
    } }
    override fun offer(event: TurnNotification): Boolean {
        if (closed || !resumed || !godotReady) return false
        return handler.post {
            if (closed || !resumed || !godotReady) {
                try { NotificationDelivery.retryPending(context) } catch (_: Exception) { }
                return@post
            }
            try { synchronized(NotificationGuard.lock) {
                NotificationStore(context).use { store ->
                    // Revalidate binding and duplicate status at delivery, not only enqueue time.
                    if (store.receive(event, System.currentTimeMillis())) {
                        receivedSink?.invoke(JSONObject(event.fields()).toString())
                        store.markPosted(event)
                    }
                }
            } } catch (_: Exception) { /* Do not expose identifiers through native errors. */ }
        }
    }
    override fun tokenChanged() { handler.post {
        if (closed || !godotReady || !resumed) return@post
        try { val s = state(); tokenSink?.invoke(JSONObject().put("generation", s.generation).put("registration_pending", s.pending).toString()) }
        catch (_: Exception) { }
    } }

    fun close() {
        closed = true; resumed = false
        NotificationRuntime.detach(this)
        handler.post {
            requests.all().forEach { fail(it, "notification_activity_closed") }
            resultSink = null; errorSink = null; receivedSink = null; tokenSink = null
        }
    }
}
