package com.aamirazeez.afteryou.nativebridge

/** FCM values are strings. This deliberately accepts only the agreed hint schema. */
internal object NotificationPolicy {
    private val keys = setOf("schema_version", "event_id", "kind", "room_id", "room_family", "revision", "binding_epoch")
    private val opaque = Regex("[A-Za-z0-9_-]{16,128}")
    private val room = Regex("[A-Za-z0-9_-]{22}")
    private val integer = Regex("[1-9][0-9]{0,15}")
    const val MAX_REVISION = 9_007_199_254_740_991L
    const val MAX_EVENTS = 256
    const val MAX_ROOMS = 128
    const val RETENTION_MS = 7L * 24 * 60 * 60 * 1000

    fun validEpoch(value: String) = value.matches(Regex("[A-Za-z0-9_-]{22}"))
    fun validEventId(value: String) = opaque.matches(value)
    fun validToken(value: String) = value.length in 16..4096 && value.all { it.code in 33..126 }

    fun parse(data: Map<String, String>): TurnNotification? {
        if (data.keys != keys || data.values.sumOf { it.length } > 1024) return null
        if (data["schema_version"] != "1") return null
        val event = data.getValue("event_id")
        val kind = data.getValue("kind")
        val roomId = data.getValue("room_id")
        val family = data.getValue("room_family")
        val epoch = data.getValue("binding_epoch")
        val rawRevision = data.getValue("revision")
        if (!validEventId(event) || !room.matches(roomId) || !validEpoch(epoch)) return null
        if (kind != "turn_ready" || family !in setOf("legacy", "relay")) return null
        if (!integer.matches(rawRevision)) return null
        val revision = rawRevision.toLongOrNull() ?: return null
        if (revision > MAX_REVISION) return null
        return TurnNotification(event, kind, roomId, family, revision, epoch)
    }
}

internal data class TurnNotification(
    val eventId: String,
    val kind: String,
    val roomId: String,
    val family: String,
    val revision: Long,
    val epoch: String
) {
    fun fields() = mapOf("schema_version" to "1", "event_id" to eventId, "kind" to kind,
        "room_id" to roomId, "room_family" to family, "revision" to revision.toString(), "binding_epoch" to epoch)
}
