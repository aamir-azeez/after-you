package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.games.SnapshotsClient
import com.google.android.gms.games.snapshot.Snapshot
import com.google.android.gms.games.snapshot.SnapshotMetadataChange
import java.util.concurrent.Executor

/** An open Saved Games slot: its bytes and, in a conflict, the other copy's bytes. */
internal class OpenedSnapshot(val snapshot: Any, val data: ByteArray, val conflict: Any?, val conflictData: ByteArray?)

/** What the bridge needs from Play Games. Callbacks carry a result or a Google status code. */
internal interface GamesClient {
    fun available(): Boolean
    fun authenticate(interactive: Boolean, done: (Boolean?, Int?) -> Unit)
    fun playerId(done: (String?, Int?) -> Unit)
    fun serverAuthCode(webClientId: String, done: (String?, Int?) -> Unit)
    fun open(name: String, done: (OpenedSnapshot?, Int?) -> Unit)
    fun resolve(opened: OpenedSnapshot, bytes: ByteArray, done: (OpenedSnapshot?, Int?) -> Unit)
    fun commit(opened: OpenedSnapshot, bytes: ByteArray, description: String, done: (Boolean, Int?) -> Unit)
    fun discard(opened: OpenedSnapshot, done: (Boolean) -> Unit)
}

/**
 * Play Games Services v2 through Google's own SDK. The SDK is initialised on first use (the
 * game asks a few seconds after launch), never at process start: the merged manifest removes
 * PlayGamesInitProvider (see the plugin manifest and build-android.ps1). A build without a
 * Play Games project id is never initialised and reports unavailable.
 */
internal class GooglePlayGamesClient(private val activity: Activity, private val worker: Executor) : GamesClient {
    private val context = activity.applicationContext
    private val appId: String = try { context.getString(R.string.game_services_project_id) } catch (_: Exception) { "" }
    @Volatile private var initialized = false

    private fun ready(): Boolean {
        if (!PlayGamesPolicy.configured(appId)) return false
        if (!initialized) synchronized(this) {
            if (!initialized) { PlayGamesSdk.initialize(context); initialized = true }
        }
        return true
    }
    private fun status(error: Exception?): Int? = (error as? ApiException)?.statusCode

    override fun available(): Boolean = try {
        PlayGamesPolicy.configured(appId) &&
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
    } catch (_: Exception) { false }

    override fun authenticate(interactive: Boolean, done: (Boolean?, Int?) -> Unit) {
        if (!ready()) { done(null, 10); return }
        val client = PlayGames.getGamesSignInClient(activity)
        val task = if (interactive) client.signIn() else client.isAuthenticated()
        task.addOnCompleteListener { result ->
            if (result.isSuccessful) done(result.result?.isAuthenticated == true, null) else done(null, status(result.exception))
        }
    }

    override fun playerId(done: (String?, Int?) -> Unit) {
        if (!ready()) { done(null, 10); return }
        PlayGames.getPlayersClient(activity).currentPlayerId.addOnCompleteListener { result ->
            if (result.isSuccessful && !result.result.isNullOrEmpty()) done(result.result, null) else done(null, status(result.exception))
        }
    }

    override fun serverAuthCode(webClientId: String, done: (String?, Int?) -> Unit) {
        if (!ready()) { done(null, 10); return }
        // Default scopes only (games_lite, drive.appdata): no extra consent screen.
        PlayGames.getGamesSignInClient(activity).requestServerSideAccess(webClientId, false).addOnCompleteListener { result ->
            if (result.isSuccessful && !result.result.isNullOrEmpty()) done(result.result, null) else done(null, status(result.exception))
        }
    }

    private fun snapshots() = PlayGames.getSnapshotsClient(activity)

    private fun read(result: SnapshotsClient.DataOrConflict<Snapshot>?): OpenedSnapshot? = try {
        if (result == null) null
        else if (result.isConflict) {
            val conflict = result.conflict ?: return null
            OpenedSnapshot(conflict.snapshot, conflict.snapshot.snapshotContents.readFully() ?: ByteArray(0), conflict,
                conflict.conflictingSnapshot.snapshotContents.readFully() ?: ByteArray(0))
        } else {
            val snapshot = result.data ?: return null
            OpenedSnapshot(snapshot, snapshot.snapshotContents.readFully() ?: ByteArray(0), null, null)
        }
    } catch (_: Exception) { null }

    override fun open(name: String, done: (OpenedSnapshot?, Int?) -> Unit) {
        if (!ready()) { done(null, 10); return }
        // Manual resolution: the game joins both copies itself, so no progress is dropped by a policy.
        snapshots().open(name, true, SnapshotsClient.RESOLUTION_POLICY_MANUAL).addOnCompleteListener(worker) { result ->
            if (!result.isSuccessful) done(null, status(result.exception)) else done(read(result.result), null)
        }
    }

    override fun resolve(opened: OpenedSnapshot, bytes: ByteArray, done: (OpenedSnapshot?, Int?) -> Unit) {
        val conflict = opened.conflict as? SnapshotsClient.SnapshotConflict
        if (conflict == null || !ready()) { done(null, null); return }
        val snapshot = conflict.snapshot
        if (!snapshot.snapshotContents.writeBytes(bytes)) { done(null, null); return }
        snapshots().resolveConflict(conflict.conflictId, snapshot).addOnCompleteListener(worker) { result ->
            if (!result.isSuccessful) done(null, status(result.exception)) else done(read(result.result), null)
        }
    }

    override fun commit(opened: OpenedSnapshot, bytes: ByteArray, description: String, done: (Boolean, Int?) -> Unit) {
        val snapshot = opened.snapshot as? Snapshot
        if (snapshot == null || opened.conflict != null || !ready() || !snapshot.snapshotContents.writeBytes(bytes)) { done(false, null); return }
        val change = SnapshotMetadataChange.Builder().setDescription(description).build()
        snapshots().commitAndClose(snapshot, change).addOnCompleteListener(worker) { result -> done(result.isSuccessful, status(result.exception)) }
    }

    override fun discard(opened: OpenedSnapshot, done: (Boolean) -> Unit) {
        val snapshot = opened.snapshot as? Snapshot
        if (snapshot == null || !ready()) { done(false); return }
        snapshots().discardAndClose(snapshot).addOnCompleteListener(worker) { result -> done(result.isSuccessful) }
    }
}
