package com.ampierelabs.afteryou.nativebridge

/** Validation only: this class never grants an entitlement. */
internal object BridgePolicy {
    fun configError(apiKey: String, playerId: String, mode: String): String? {
        if (!playerId.matches(Regex("[A-Za-z0-9_-]{8,128}"))) return "invalid_player_id"
        if (apiKey.length !in 12..256 || !apiKey.matches(Regex("[A-Za-z0-9_-]+"))) return "invalid_public_key"
        return when (mode) {
            "test_store" -> if (apiKey.startsWith("test_")) null else "store_key_mismatch"
            "google_play" -> if (apiKey.startsWith("goog_")) null else "store_key_mismatch"
            else -> "unsupported_store"
        }
    }

    fun validStorageName(name: String): Boolean = name.matches(Regex("[a-z][a-z0-9_.-]{0,63}"))
    fun validStorageValue(value: String): Boolean = value.toByteArray(Charsets.UTF_8).size <= 16_384
}
