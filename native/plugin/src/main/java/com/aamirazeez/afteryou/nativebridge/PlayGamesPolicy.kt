package com.aamirazeez.afteryou.nativebridge

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Play Games rules with no Android or SDK types, so JVM tests cover them: what configuration
 * turns the feature on, the shapes the bridge accepts, the one-way player key, and how SDK status
 * codes become the few codes the game knows. No platform text or account id ever leaves here.
 */
internal object PlayGamesPolicy {
    private val APP_ID = Regex("[0-9]{6,20}")
    private val WEB_CLIENT_ID = Regex("[0-9]{6,20}-[a-z0-9]{8,64}\\.apps\\.googleusercontent\\.com")
    private val SNAPSHOT_NAME = Regex("[a-z][a-z0-9-]{0,63}")
    private val HANDLE = Regex("[a-f0-9]{32}")
    /** Saved Games allows 3 MiB a slot. */
    const val MAX_SNAPSHOT_BYTES = 3 * 1024 * 1024
    /** Base64 of the largest slot, plus padding. */
    const val MAX_SNAPSHOT_BASE64 = (MAX_SNAPSHOT_BYTES / 3 + 1) * 4
    const val MAX_DESCRIPTION = 100
    const val QUIET_TIMEOUT_MS = 14_000L
    const val SIGN_IN_TIMEOUT_MS = 115_000L
    const val SNAPSHOT_TIMEOUT_MS = 28_000L

    /** The public Play Games project id from the build; an unconfigured build has "". */
    fun configured(appId: String?): Boolean = appId != null && APP_ID.matches(appId)
    fun validWebClientId(value: String): Boolean = WEB_CLIENT_ID.matches(value)
    fun validSnapshotName(value: String): Boolean = SNAPSHOT_NAME.matches(value)
    fun validHandle(value: String): Boolean = HANDLE.matches(value)
    fun validDescription(value: String): Boolean = value.length <= MAX_DESCRIPTION && value.none { it.isISOControl() }
    fun validBase64Length(value: String): Boolean = value.length <= MAX_SNAPSHOT_BASE64

    /** A one-way key that tells accounts apart on this phone; the Play Games id itself stays native. */
    fun playerKey(playerId: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest("after-you:play_games:$playerId".toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    fun newHandle(random: SecureRandom = SecureRandom()): String {
        val bytes = ByteArray(16).also { random.nextBytes(it) }
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Google status codes (CommonStatusCodes and GamesClientStatusCodes, as numbers so this class
     * needs no SDK) to the game's codes. Anything unknown is "failed".
     */
    fun errorCode(status: Int?): String = when (status) {
        4 -> "signed_out"           // SIGN_IN_REQUIRED
        7 -> "offline"              // NETWORK_ERROR
        16, 12501 -> "cancelled"    // CANCELED, SIGN_IN_CANCELLED
        15 -> "timeout"             // TIMEOUT
        1, 2, 3, 9, 17, 18 -> "unavailable" // SERVICE_MISSING/UPDATE/DISABLED/INVALID, API_NOT_CONNECTED, SERVICE_UPDATING
        10 -> "not_configured"      // DEVELOPER_ERROR: app id, SHA-1 or OAuth client mismatch
        26507, 26502 -> "offline"   // GamesClientStatusCodes NETWORK_ERROR_NO_DATA, CLIENT_RECONNECT_REQUIRED
        else -> "failed"
    }
}

/** Open snapshots by opaque handle. Bounded: opening one more closes nothing, it is refused. */
internal class SnapshotHandles<T>(private val max: Int = 2, private val newHandle: () -> String = { PlayGamesPolicy.newHandle() }) {
    private val open = LinkedHashMap<String, T>()
    @Synchronized fun put(value: T): String? {
        if (open.size >= max) return null
        var handle = newHandle()
        while (open.containsKey(handle)) handle = newHandle()
        open[handle] = value
        return handle
    }
    @Synchronized fun get(handle: String): T? = open[handle]
    @Synchronized fun take(handle: String): T? = open.remove(handle)
    @Synchronized fun drain(): List<T> = open.values.toList().also { open.clear() }
    @Synchronized fun size(): Int = open.size
}
