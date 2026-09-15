package com.aamirazeez.afteryou.nativebridge

import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Synthetic app-private DB only; never posts notifications or opens the retained game vault. */
@RunWith(AndroidJUnit4::class)
class NotificationStoreDeviceTest {
    private val token = "synthetic_token_" + "t".repeat(40)
    private val epoch = "a".repeat(22)
    private fun event(n: Int, room: String = "r".repeat(22)) = TurnNotification(
        "synthetic_event_" + n.toString().padStart(8, '0'), "turn_ready", room, "relay", n.toLong(), epoch)

    private fun withStore(test: (NotificationStore, ContextWrapper) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(context.cacheDir, "notification-test-" + UUID.randomUUID()).apply { check(mkdir()) }
        val isolated = object : ContextWrapper(context) { override fun getNoBackupFilesDir() = folder }
        try { NotificationStore(isolated).use { test(it, isolated) } }
        finally {
            check(folder.canonicalFile.parentFile == context.cacheDir.canonicalFile)
            check(folder.name.startsWith("notification-test-"))
            folder.deleteRecursively()
        }
    }

    private fun enable(store: NotificationStore) {
        store.setOptedIn(true); store.noteToken(token); assertTrue(store.bind(epoch, token, store.registration().generation))
    }

    @Test fun defaultsOffAndRejectsAStaleTokenAcknowledgement() = withStore { store, _ ->
        assertFalse(store.registration().optedIn)
        assertFalse(store.receive(event(1), 1000))
        store.setOptedIn(true); store.noteToken(token)
        store.noteToken(token + "rotated")
        assertFalse(store.bind(epoch, token, store.registration().generation))
        assertTrue(store.registration().pending)
        assertTrue(store.bind(epoch, token + "rotated", store.registration().generation))
        assertFalse(store.registration().pending)
    }

    @Test fun pendingPostRetriesButPostedDuplicateAndOlderRevisionDoNot() = withStore { store, _ ->
        enable(store)
        assertTrue(store.receive(event(2), 1000))
        assertTrue(store.receive(event(2), 1001))
        store.markPosted(event(2))
        assertFalse(store.receive(event(2), 1002))
        assertFalse(store.receive(event(1), 1003))
        assertFalse(store.receive(event(2).copy(eventId = "another_event_12345678"), 1004))
        assertFalse(store.receive(event(2).copy(roomId = "s".repeat(22)), 1005))
        assertTrue(store.receive(event(3), 1006))
    }

    @Test fun onlyTappedBoundEventsBecomeTypedRoutesAndAcknowledgementPersists() = withStore { store, context ->
        enable(store); assertTrue(store.receive(event(1), 1000)); store.markPosted(event(1))
        assertNull(store.pendingRoute(1001))
        assertTrue(store.markTapped(event(1).eventId))
        assertEquals(event(1), store.pendingRoute(1001))
        assertTrue(store.acknowledge(event(1).eventId))
        assertNull(store.pendingRoute(1001))
        NotificationStore(context).use { reopened ->
            assertNull(reopened.pendingRoute(1002))
            assertFalse(reopened.receive(event(1), 1002))
        }
    }

    @Test fun disableAndAccountRebindingCannotLeakOldRoutes() = withStore { store, _ ->
        enable(store); assertTrue(store.receive(event(1), 1000)); assertTrue(store.markTapped(event(1).eventId))
        assertTrue(store.bind("b".repeat(22), token, store.registration().generation))
        assertNull(store.pendingRoute(1001))
        assertFalse(store.receive(event(2), 1002))
        store.setOptedIn(false)
        assertFalse(store.registration().optedIn)
        assertEquals("", store.registration().epoch)
        assertFalse(store.markTapped(event(1).eventId))
    }

    @Test fun newestRevisionReplacesPendingPostsAndStorageIsCapped() = withStore { store, _ ->
        enable(store); assertTrue(store.receive(event(1), 1000)); assertTrue(store.receive(event(2), 1001))
        assertEquals(listOf(event(2)), store.pendingPosts(1002))
        for (index in 3..300) assertTrue(store.receive(event(index, ("r" + index.toString().padStart(21, '0'))), 1000L + index))
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM events", null).use {
            assertTrue(it.moveToFirst()); assertTrue(it.getInt(0) <= NotificationPolicy.MAX_EVENTS)
        }
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM watermark", null).use {
            assertTrue(it.moveToFirst()); assertTrue(it.getInt(0) <= NotificationPolicy.MAX_ROOMS)
        }
        assertTrue(store.pendingPosts(2000).size <= 32)
        assertTrue(store.pendingPosts(NotificationPolicy.RETENTION_MS + 10000).isEmpty())
    }

    @Test fun identityClearPreservesPreferenceButRejectsOldAcknowledgementAndTap() = withStore { store, _ ->
        enable(store)
        val oldGeneration = store.registration().generation
        assertTrue(store.receive(event(1), 1000))
        assertTrue(store.markTapped(event(1).eventId))
        val cleared = store.clearBinding()
        assertTrue(cleared.optedIn)
        assertTrue(cleared.generation > oldGeneration)
        assertFalse(store.bind(epoch, token, oldGeneration))
        assertNull(store.pendingRoute(1001))
        assertFalse(store.receive(event(2), 1002))
        assertTrue(store.bind("b".repeat(22), token, cleared.generation))
        assertFalse(store.receive(event(2), 1003))
        assertTrue(store.receive(event(2).copy(epoch = "b".repeat(22)), 1004))
    }

    @Test fun tokenRotationCannotBindTheOldTokenButDoesNotChangeAccountGeneration() = withStore { store, _ ->
        enable(store)
        val generation = store.registration().generation
        store.noteToken(token + "rotated")
        assertEquals(generation, store.registration().generation)
        assertFalse(store.bind(epoch, token, generation))
        assertTrue(store.bind(epoch, token + "rotated", generation))
        store.setOptedIn(false)
        assertFalse(store.bind(epoch, token + "rotated", generation))
    }
}
