package com.aamirazeez.afteryou.nativebridge

import android.Manifest
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Real Android loop/SQLite, fake provider+permission UI. No retained game or live token access. */
@RunWith(AndroidJUnit4::class)
class NotificationBridgeDeviceTest {
    private class Host : NotificationHost {
        var granted = false
        var permissionRequests = 0
        override fun permissionGranted() = granted
        override fun channelEnabled() = granted
        override fun createChannels() = Unit
        override fun cancelVisible() = Unit
        override fun requestPermission(requestCode: Int): Boolean { permissionRequests++; return true }
    }
    private class Client : NotificationClient {
        override var configured = true
        var auto = false
        var calls = 0
        var tokenCallback: ((String?) -> Unit)? = null
        var deleteCallback: ((Boolean) -> Unit)? = null
        override fun autoInit(enabled: Boolean) { auto = enabled }
        override fun token(done: (String?) -> Unit) { calls++; tokenCallback = done }
        override fun deleteToken(done: (Boolean) -> Unit) { calls++; deleteCallback = done }
    }
    private class Harness(val context: ContextWrapper) {
        val host = Host()
        val client = Client()
        val results = mutableMapOf<String, JSONObject>()
        val errors = mutableMapOf<String, String>()
        val refreshes = mutableListOf<JSONObject>()
        val bridge = NotificationBridge(context, host, client,
            { id, _, json -> results[id] = JSONObject(json) },
            { id, _, code -> errors[id] = code },
            { refreshes.add(JSONObject(it)) }, {})
        fun drain() = InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        fun enable() { host.granted = true; bridge.requestPermission("enable"); drain(); assertTrue(results["enable"]!!.getBoolean("opted_in")) }
        fun completeToken(token: String) { client.tokenCallback!!.invoke(token); drain() }
        fun state() = NotificationStore(context).use { it.registration() }
    }
    private fun isolated(action: (Harness) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(base.cacheDir, "notification-bridge-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        val context = object : ContextWrapper(base) { override fun getNoBackupFilesDir() = folder }
        val h = Harness(context)
        try { action(h) } finally {
            h.bridge.close(); h.drain()
            check(folder.canonicalFile.parentFile == base.cacheDir.canonicalFile)
            check(folder.name.startsWith("notification-bridge-test-"))
            check(folder.deleteRecursively())
        }
    }
    private val token = "synthetic_token_" + "x".repeat(48)
    private val epoch = "a".repeat(22)

    @Test fun unconfiguredStatusAndRoutesDoNotStartProvider() = isolated { h ->
        h.client.configured = false
        h.bridge.status("status"); h.bridge.pendingRoute("route"); h.bridge.getToken("token"); h.drain()
        assertFalse(h.results["status"]!!.getBoolean("supported"))
        assertEquals(0, h.results["route"]!!.getJSONObject("route").length())
        assertEquals("notification_unconfigured", h.errors["token"])
        assertEquals(0, h.client.calls)
        assertFalse(h.client.auto)
    }

    @Test fun permissionNeedsExplicitRequestAndActualGrant() = isolated { h ->
        h.bridge.requestPermission("deny"); h.drain()
        assertEquals(1, h.host.permissionRequests)
        h.bridge.permissionResult(NotificationBridge.PERMISSION_REQUEST, emptyArray()); h.drain()
        assertFalse(h.results["deny"]!!.getBoolean("opted_in"))
        assertFalse(h.client.auto)
        h.bridge.requestPermission("grant"); h.drain()
        h.host.granted = true
        h.bridge.permissionResult(NotificationBridge.PERMISSION_REQUEST, arrayOf(Manifest.permission.POST_NOTIFICATIONS)); h.drain()
        assertTrue(h.results["grant"]!!.getBoolean("opted_in"))
        assertEquals(0, h.client.calls) // Permission alone never retrieves a registration token.
        h.bridge.getToken("token"); h.drain(); h.completeToken(token)
        assertTrue(h.results["token"]!!.getString("token") == token)
        assertTrue(h.client.auto)
    }

    @Test fun tokenResultAfterIdentityClearCannotRestoreBinding() = isolated { h ->
        h.enable(); h.bridge.getToken("old-token"); h.drain()
        h.bridge.clearBinding("clear"); h.drain()
        h.completeToken(token)
        assertEquals("notification_binding_changed", h.errors["old-token"])
        assertTrue(h.state().epoch.isEmpty())
        assertTrue(h.state().tokenHash.isEmpty())
        assertTrue(h.results["clear"]!!.getBoolean("cleared"))
    }

    @Test fun matchingOnNewTokenBeforeGetTokenCompletionIsNotAFalseStaleFailure() = isolated { h ->
        h.enable(); h.bridge.getToken("token"); h.drain()
        NotificationStore(h.context).use { it.noteToken(token) } // What onNewToken does.
        h.completeToken(token)
        assertFalse(h.errors.containsKey("token"))
        val generation = h.results["token"]!!.getLong("generation")
        h.bridge.setBinding(epoch, token, generation, "bind"); h.drain()
        assertTrue(h.results["bind"]!!.getBoolean("bound"))
        h.bridge.clearBinding("clear"); h.drain()
        h.bridge.setBinding(epoch, token, generation, "stale"); h.drain()
        assertEquals("notification_binding_changed", h.errors["stale"])
    }

    @Test fun foregroundSignalDeduplicatesAndAccountClearRejectsQueuedOldEvent() = isolated { h ->
        h.enable(); h.bridge.getToken("token"); h.drain(); h.completeToken(token)
        h.bridge.setBinding(epoch, token, h.state().generation, "bind"); h.drain()
        h.bridge.ready(); h.bridge.resume(); h.drain()
        val event = TurnNotification("event_" + "x".repeat(22), "turn_ready", "r".repeat(22), "relay", 2, epoch)
        NotificationDelivery.receive(h.context, event); h.drain()
        NotificationDelivery.receive(h.context, event); h.drain()
        assertEquals(1, h.refreshes.size)
        assertEquals(7, h.refreshes[0].length())
        h.bridge.clearBinding("clear"); h.drain()
        NotificationDelivery.receive(h.context, event.copy(eventId = "event_" + "y".repeat(22), revision = 3)); h.drain()
        assertEquals(1, h.refreshes.size)
    }

    @Test fun providerDeletionFailureStillDisablesLocalDeliveryTruthfully() = isolated { h ->
        h.enable(); h.bridge.getToken("token"); h.drain(); h.completeToken(token)
        h.bridge.setBinding(epoch, token, h.state().generation, "bind"); h.drain()
        h.bridge.disable("disable"); h.drain()
        assertFalse(h.state().optedIn)
        assertTrue(h.state().epoch.isEmpty())
        h.client.deleteCallback!!.invoke(false); h.drain()
        assertTrue(h.results["disable"]!!.getBoolean("disabled"))
        assertFalse(h.results["disable"]!!.getBoolean("token_deleted"))
        assertFalse(h.client.auto)
    }

    @Test fun handledForegroundHintCannotBecomeALaterBackgroundPost() = isolated { h ->
        h.enable(); h.bridge.getToken("token"); h.drain(); h.completeToken(token)
        h.bridge.setBinding(epoch, token, h.state().generation, "bind"); h.drain()
        h.bridge.ready(); h.bridge.resume(); h.drain()
        val event = TurnNotification("event_" + "f".repeat(22), "turn_ready", "r".repeat(22), "relay", 3, epoch)
        // Run within one actual main-loop callback: offer() queues delivery but cannot run it
        // until this callback returns. Queuing alone must not acknowledge the durable hint.
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            NotificationDelivery.receive(h.context, event)
            NotificationStore(h.context).use { assertEquals(listOf(event), it.pendingPosts(System.currentTimeMillis())) }
            assertTrue(h.refreshes.isEmpty())
        }
        h.drain()
        assertEquals(1, h.refreshes.size)
        NotificationStore(h.context).use { assertTrue(it.pendingPosts(System.currentTimeMillis()).isEmpty()) }
        h.bridge.pause()
        NotificationDelivery.retryPending(h.context)
        NotificationDelivery.receive(h.context, event)
        h.drain()
        // A reopened SQLite connection must still see consumption. This proves the OS-post
        // retry has no eligible hint, even if platform notification permission is denied.
        NotificationStore(h.context).use {
            assertTrue(it.pendingPosts(System.currentTimeMillis()).isEmpty())
            assertFalse(it.receive(event, System.currentTimeMillis()))
        }
        assertEquals(1, h.refreshes.size)
    }
}
