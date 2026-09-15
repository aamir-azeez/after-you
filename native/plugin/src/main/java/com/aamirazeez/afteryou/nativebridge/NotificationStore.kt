package com.aamirazeez.afteryou.nativebridge

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.File
import java.security.MessageDigest

/** All notification code lives in the default app process and shares this lock. */
internal object NotificationGuard { val lock = Any() }

internal data class NotificationRegistration(
    val optedIn: Boolean, val epoch: String, val tokenHash: String,
    val registeredHash: String, val generation: Long
) { val pending: Boolean get() = optedIn && (tokenHash.isEmpty() || registeredHash != tokenHash || epoch.isEmpty()) }

/** No credentials, photos, recordings or raw FCM tokens are stored here. Not backed up. */
internal class NotificationStore(context: Context) : SQLiteOpenHelper(context, databasePath(context), null, 1) {
    companion object {
        private fun databasePath(context: Context): String {
            val directory = File(context.noBackupFilesDir, "after-you-notifications")
            check(directory.isDirectory || directory.mkdirs())
            return File(directory, "events.db").absolutePath
        }
        fun hash(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE registration (id INTEGER PRIMARY KEY CHECK(id=1), opted INTEGER NOT NULL, epoch TEXT NOT NULL, token_hash TEXT NOT NULL, registered_hash TEXT NOT NULL, generation INTEGER NOT NULL)")
        db.execSQL("INSERT INTO registration VALUES (1,0,'','','',0)")
        db.execSQL("CREATE TABLE events (event_id TEXT PRIMARY KEY, kind TEXT NOT NULL, room_id TEXT NOT NULL, family TEXT NOT NULL, revision INTEGER NOT NULL, epoch TEXT NOT NULL, received INTEGER NOT NULL, posted INTEGER NOT NULL DEFAULT 0, tapped INTEGER NOT NULL DEFAULT 0, acked INTEGER NOT NULL DEFAULT 0)")
        db.execSQL("CREATE TABLE watermark (kind TEXT NOT NULL, room_id TEXT NOT NULL, family TEXT NOT NULL, revision INTEGER NOT NULL, event_id TEXT NOT NULL, received INTEGER NOT NULL, PRIMARY KEY(kind,room_id,family))")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Never silently discard an unknown local schema.
        throw IllegalStateException("notification_schema_unavailable")
    }

    fun registration(): NotificationRegistration = synchronized(NotificationGuard.lock) {
        readableDatabase.rawQuery("SELECT opted,epoch,token_hash,registered_hash,generation FROM registration WHERE id=1", null).use {
            check(it.moveToFirst())
            NotificationRegistration(it.getInt(0) != 0, it.getString(1), it.getString(2), it.getString(3), it.getLong(4))
        }
    }

    fun setOptedIn(enabled: Boolean): NotificationRegistration = synchronized(NotificationGuard.lock) {
        transaction { db ->
            if (!enabled) {
                db.execSQL("UPDATE registration SET opted=0,epoch='',registered_hash='',generation=generation+1 WHERE id=1")
                db.delete("events", null, null); db.delete("watermark", null, null)
            } else db.execSQL("UPDATE registration SET opted=1,generation=generation+1 WHERE id=1 AND opted=0")
        }
        registration()
    }

    fun noteToken(token: String) = synchronized(NotificationGuard.lock) {
        require(NotificationPolicy.validToken(token))
        val digest = hash(token)
        writableDatabase.execSQL("UPDATE registration SET token_hash=? WHERE id=1 AND token_hash<>?", arrayOf(digest, digest))
    }

    /** Identity/credential changed. Preserve preference, invalidate every pending acknowledgement. */
    fun clearBinding(): NotificationRegistration = synchronized(NotificationGuard.lock) {
        transaction { db ->
            db.execSQL("UPDATE registration SET epoch='',registered_hash='',generation=generation+1 WHERE id=1")
            db.delete("events", null, null); db.delete("watermark", null, null)
        }
        registration()
    }

    /** Epoch changes erase hints from the previous account binding. */
    fun bind(epoch: String, acknowledgedToken: String, expectedGeneration: Long): Boolean = synchronized(NotificationGuard.lock) {
        if (!NotificationPolicy.validEpoch(epoch) || !NotificationPolicy.validToken(acknowledgedToken)) return@synchronized false
        val state = registration()
        val digest = hash(acknowledgedToken)
        if (!state.optedIn || state.generation != expectedGeneration || state.tokenHash != digest) return@synchronized false
        transaction { db ->
            if (state.epoch != epoch) { db.delete("events", null, null); db.delete("watermark", null, null) }
            db.execSQL("UPDATE registration SET epoch=?,registered_hash=? WHERE id=1", arrayOf(epoch, digest))
        }
        true
    }

    /** Returns true only for a new or previously unposted event, under the current binding. */
    fun receive(event: TurnNotification, now: Long): Boolean = synchronized(NotificationGuard.lock) {
        val state = registration()
        if (!state.optedIn || state.epoch != event.epoch) return@synchronized false
        var accepted = false
        transaction { db ->
            prune(db, now)
            db.rawQuery("SELECT event_id,kind,room_id,family,revision,epoch,posted FROM events WHERE event_id=?", arrayOf(event.eventId)).use { row ->
                if (row.moveToFirst()) {
                    accepted = readEvent(row) == event && row.getInt(6) == 0 && isLatest(db, event)
                    return@transaction
                }
            }
            db.rawQuery("SELECT revision FROM watermark WHERE kind=? AND room_id=? AND family=?", arrayOf(event.kind, event.roomId, event.family)).use {
                if (it.moveToFirst() && it.getLong(0) >= event.revision) return@transaction
            }
            db.insertOrThrow("events", null, values(event, now))
            val watermark = values(event, now).apply { remove("epoch") }
            db.insertWithOnConflict("watermark", null, watermark, SQLiteDatabase.CONFLICT_REPLACE)
            prune(db, now)
            accepted = true
        }
        accepted
    }

    fun markPosted(event: TurnNotification) = synchronized(NotificationGuard.lock) {
        writableDatabase.execSQL("UPDATE events SET posted=1 WHERE event_id=? AND epoch=?", arrayOf(event.eventId, event.epoch))
    }

    fun pendingPosts(now: Long): List<TurnNotification> = synchronized(NotificationGuard.lock) {
        prune(writableDatabase, now)
        val state = registration()
        if (!state.optedIn || state.epoch.isEmpty()) return@synchronized emptyList()
        readableDatabase.rawQuery("SELECT event_id,kind,room_id,family,revision,epoch FROM events WHERE posted=0 AND epoch=? ORDER BY received DESC,event_id LIMIT 32", arrayOf(state.epoch)).use { row ->
            val result = mutableListOf<TurnNotification>()
            while (row.moveToNext()) { val e = readEvent(row); if (isLatest(readableDatabase, e)) result.add(e) }
            result
        }
    }

    fun markTapped(eventId: String): Boolean = synchronized(NotificationGuard.lock) {
        if (!NotificationPolicy.validEventId(eventId)) return@synchronized false
        val state = registration()
        if (!state.optedIn || state.epoch.isEmpty()) return@synchronized false
        writableDatabase.update("events", ContentValues().apply { put("tapped", 1) }, "event_id=? AND epoch=? AND acked=0", arrayOf(eventId, state.epoch)) == 1
    }

    fun pendingRoute(now: Long): TurnNotification? = synchronized(NotificationGuard.lock) {
        prune(writableDatabase, now)
        val state = registration()
        if (!state.optedIn || state.epoch.isEmpty()) return@synchronized null
        readableDatabase.rawQuery("SELECT event_id,kind,room_id,family,revision,epoch FROM events WHERE tapped=1 AND acked=0 AND epoch=? ORDER BY received DESC,event_id LIMIT 1", arrayOf(state.epoch)).use {
            if (it.moveToFirst()) readEvent(it) else null
        }
    }

    fun acknowledge(eventId: String): Boolean = synchronized(NotificationGuard.lock) {
        if (!NotificationPolicy.validEventId(eventId)) return@synchronized false
        val state = registration()
        writableDatabase.update("events", ContentValues().apply { put("acked", 1) }, "event_id=? AND epoch=? AND tapped=1", arrayOf(eventId, state.epoch)) == 1
    }

    private fun values(e: TurnNotification, now: Long) = ContentValues().apply {
        put("event_id", e.eventId); put("kind", e.kind); put("room_id", e.roomId); put("family", e.family)
        put("revision", e.revision); put("epoch", e.epoch); put("received", now)
    }

    private fun readEvent(row: Cursor) = TurnNotification(row.getString(0), row.getString(1), row.getString(2), row.getString(3), row.getLong(4), row.getString(5))
    private fun isLatest(db: SQLiteDatabase, e: TurnNotification): Boolean = db.rawQuery("SELECT event_id FROM watermark WHERE kind=? AND room_id=? AND family=?", arrayOf(e.kind, e.roomId, e.family)).use {
        it.moveToFirst() && it.getString(0) == e.eventId
    }

    private fun prune(db: SQLiteDatabase, now: Long) {
        db.delete("events", "received<?", arrayOf((now - NotificationPolicy.RETENTION_MS).toString()))
        db.delete("watermark", "received<?", arrayOf((now - NotificationPolicy.RETENTION_MS).toString()))
        db.execSQL("DELETE FROM events WHERE event_id IN (SELECT event_id FROM events ORDER BY received DESC,event_id LIMIT -1 OFFSET ${NotificationPolicy.MAX_EVENTS})")
        db.execSQL("DELETE FROM watermark WHERE rowid IN (SELECT rowid FROM watermark ORDER BY received DESC,rowid DESC LIMIT -1 OFFSET ${NotificationPolicy.MAX_ROOMS})")
    }

    private inline fun transaction(action: (SQLiteDatabase) -> Unit) {
        val db = writableDatabase
        db.beginTransaction()
        try { action(db); db.setTransactionSuccessful() } finally { db.endTransaction() }
    }
}
