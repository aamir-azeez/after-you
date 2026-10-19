package com.aamirazeez.afteryou.nativebridge

import android.os.Handler
import android.os.Looper
import android.util.Base64
import org.json.JSONObject

/**
 * The games_* requests from Godot: one answer per request id (result or error), each with a
 * deadline a little shorter than the game's own, so a late SDK callback never answers twice.
 * Only known codes, a one-way player key, a one-time server auth code and slot bytes leave here,
 * plus the Play Games gamer name, and that only when the game asks for it with player_name.
 */
internal class PlayGamesBridge(
    private val client: GamesClient,
    result: (String, String, String) -> Unit,
    error: (String, String, String) -> Unit
) {
    private val handler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val requests = NotificationRequests()
    private val deadlines = mutableMapOf<NotificationRequests.Ticket, Runnable>()
    private val handles = SnapshotHandles<OpenedSnapshot>()
    private var resultSink: ((String, String, String) -> Unit)? = result
    private var errorSink: ((String, String, String) -> Unit)? = error
    @Volatile private var closed = false

    fun available(): Boolean = try { !closed && client.available() } catch (_: Exception) { false }

    private fun call(id: String, operation: String, timeout: Long, action: (NotificationRequests.Ticket) -> Unit) {
        handler.post {
            if (closed) return@post
            val ticket = synchronized(lock) { requests.begin(id, operation) } ?: return@post
            val deadline = Runnable { fail(ticket, "timeout") }
            synchronized(lock) { deadlines[ticket] = deadline }
            handler.postDelayed(deadline, timeout)
            try { action(ticket) } catch (_: Exception) { fail(ticket, "failed") }
        }
    }
    private fun current(ticket: NotificationRequests.Ticket): Boolean = synchronized(lock) { requests.current(ticket) }
    private fun finish(ticket: NotificationRequests.Ticket): Boolean {
        val deadline = synchronized(lock) {
            if (!requests.finish(ticket)) return false
            deadlines.remove(ticket)
        }
        deadline?.let { handler.removeCallbacks(it) }
        return true
    }
    /** False when the request already expired: the caller then cleans up what it opened. */
    private fun success(ticket: NotificationRequests.Ticket, data: JSONObject): Boolean {
        if (!finish(ticket)) return false
        resultSink?.invoke(ticket.id, ticket.operation, data.toString())
        return true
    }
    private fun fail(ticket: NotificationRequests.Ticket, code: String) {
        if (finish(ticket)) errorSink?.invoke(ticket.id, ticket.operation, code)
    }
    private fun failStatus(ticket: NotificationRequests.Ticket, status: Int?) = fail(ticket, PlayGamesPolicy.errorCode(status))

    fun status(id: String) = call(id, "status", PlayGamesPolicy.QUIET_TIMEOUT_MS) { authenticate(it, false) }
    fun signIn(id: String) = call(id, "sign_in", PlayGamesPolicy.SIGN_IN_TIMEOUT_MS) { authenticate(it, true) }

    private fun authenticate(ticket: NotificationRequests.Ticket, interactive: Boolean) {
        if (!client.available()) { fail(ticket, "unavailable"); return }
        client.authenticate(interactive) { signedIn, status ->
            when {
                signedIn == null -> failStatus(ticket, status)
                !signedIn -> success(ticket, JSONObject().put("signed_in", false))
                else -> client.playerId { player, playerStatus ->
                    if (player.isNullOrEmpty() || player.length > 256) failStatus(ticket, playerStatus)
                    else success(ticket, JSONObject().put("signed_in", true).put("player_key", PlayGamesPolicy.playerKey(player)))
                }
            }
        }
    }

    /** The gamer name, read only on this request (never during sign-in or status) and never with UI. */
    fun playerName(id: String) = call(id, "player_name", PlayGamesPolicy.QUIET_TIMEOUT_MS) { ticket ->
        if (!client.available()) { fail(ticket, "unavailable"); return@call }
        client.authenticate(false) { signedIn, status ->
            when (signedIn) {
                null -> failStatus(ticket, status)
                false -> fail(ticket, "signed_out")
                true -> client.playerName { name, nameStatus ->
                    when {
                        name == null -> failStatus(ticket, nameStatus)
                        !PlayGamesPolicy.validPlayerName(name) -> fail(ticket, "failed")
                        else -> success(ticket, JSONObject().put("name", name))
                    }
                }
            }
        }
    }

    fun credential(webClientId: String, id: String) = call(id, "credential", PlayGamesPolicy.QUIET_TIMEOUT_MS) { ticket ->
        if (!PlayGamesPolicy.validWebClientId(webClientId)) { fail(ticket, "not_configured"); return@call }
        client.serverAuthCode(webClientId) { code, status ->
            if (code.isNullOrEmpty() || code.length > 2048) failStatus(ticket, status)
            else success(ticket, JSONObject().put("credential", JSONObject().put("server_auth_code", code)))
        }
    }

    /** One sync runs at a time: a new open closes any slot an earlier, abandoned sync left open. */
    fun snapshotOpen(name: String, id: String) = call(id, "snapshot_open", PlayGamesPolicy.SNAPSHOT_TIMEOUT_MS) { ticket ->
        if (!PlayGamesPolicy.validSnapshotName(name)) { fail(ticket, "failed"); return@call }
        handles.drain().forEach { left -> try { client.discard(left) { } } catch (_: Exception) { } }
        client.open(name) { opened, status -> answerOpened(ticket, opened, status) }
    }

    private fun answerOpened(ticket: NotificationRequests.Ticket, opened: OpenedSnapshot?, status: Int?) {
        if (opened == null) { failStatus(ticket, status); return }
        if (opened.data.size > PlayGamesPolicy.MAX_SNAPSHOT_BYTES || (opened.conflictData?.size ?: 0) > PlayGamesPolicy.MAX_SNAPSHOT_BYTES || !current(ticket)) {
            client.discard(opened) { }
            fail(ticket, "failed")
            return
        }
        val handle = handles.put(opened)
        if (handle == null) { client.discard(opened) { }; fail(ticket, "busy"); return }
        val data = JSONObject().put("handle", handle).put("data", encode(opened.data))
        if (opened.conflictData != null) data.put("conflict", JSONObject().put("data", encode(opened.conflictData)))
        // The request expired while the answer was built: nobody will close this slot, so close it here.
        if (!success(ticket, data)) handles.take(handle)?.let { client.discard(it) { } }
    }

    fun snapshotResolve(handle: String, data: String, id: String) = call(id, "snapshot_resolve", PlayGamesPolicy.SNAPSHOT_TIMEOUT_MS) { ticket ->
        val bytes = decode(data)
        val opened = if (PlayGamesPolicy.validHandle(handle)) handles.take(handle) else null
        if (opened == null || bytes == null || opened.conflict == null) {
            opened?.let { client.discard(it) { } }
            fail(ticket, "failed"); return@call
        }
        client.resolve(opened, bytes) { next, status -> answerOpened(ticket, next, status) }
    }

    fun snapshotCommit(handle: String, data: String, description: String, id: String) = call(id, "snapshot_commit", PlayGamesPolicy.SNAPSHOT_TIMEOUT_MS) { ticket ->
        val bytes = decode(data)
        val opened = if (PlayGamesPolicy.validHandle(handle)) handles.take(handle) else null
        if (opened == null || bytes == null || opened.conflict != null || !PlayGamesPolicy.validDescription(description)) {
            opened?.let { client.discard(it) { } }
            fail(ticket, "failed"); return@call
        }
        client.commit(opened, bytes, description) { committed, status ->
            if (committed) success(ticket, JSONObject().put("committed", true)) else failStatus(ticket, status)
        }
    }

    fun snapshotDiscard(handle: String, id: String) = call(id, "snapshot_discard", PlayGamesPolicy.QUIET_TIMEOUT_MS) { ticket ->
        val opened = if (PlayGamesPolicy.validHandle(handle)) handles.take(handle) else null
        if (opened == null) { success(ticket, JSONObject().put("discarded", false)); return@call }
        client.discard(opened) { discarded -> success(ticket, JSONObject().put("discarded", discarded)) }
    }

    private fun encode(bytes: ByteArray): String = if (bytes.isEmpty()) "" else Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(value: String): ByteArray? {
        if (!PlayGamesPolicy.validBase64Length(value)) return null
        return try { if (value.isEmpty()) ByteArray(0) else Base64.decode(value, Base64.NO_WRAP) } catch (_: Exception) { null }
            ?.takeIf { it.size <= PlayGamesPolicy.MAX_SNAPSHOT_BYTES }
    }

    fun close() {
        closed = true
        handler.post {
            synchronized(lock) { requests.all() }.forEach { fail(it, "unavailable") }
            handles.drain().forEach { left -> try { client.discard(left) { } } catch (_: Exception) { } }
            resultSink = null; errorSink = null
        }
    }
}
