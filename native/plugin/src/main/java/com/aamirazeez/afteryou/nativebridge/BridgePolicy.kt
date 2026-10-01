package com.aamirazeez.afteryou.nativebridge

/** Validation only: this class never grants an entitlement. */
internal object BridgePolicy {
    fun configError(apiKey: String, playerId: String, mode: String, allowTestStore: Boolean = false): String? {
        // The bridge supplies the compile-time build flag; caller configuration cannot
        // enable Test Store in Release. Tester codes never configure a purchase SDK.
        val prefix = when {
            mode == "google_play" -> "goog_"
            mode == "test_store" && allowTestStore -> "test_"
            else -> return "unsupported_store"
        }
        if (!playerId.matches(Regex("[A-Za-z0-9_-]{8,128}"))) return "invalid_player_id"
        if (apiKey.length !in 12..256 || !apiKey.matches(Regex("[A-Za-z0-9_-]+"))) return "invalid_public_key"
        return if (apiKey.startsWith(prefix)) null else "store_key_mismatch"
    }

    // Never adopt a preconfigured SDK whose store/key/identity this bridge did not validate.
    fun sdkStateError(bridgeConfigured: Boolean, sdkConfigured: Boolean): String? = when {
        !bridgeConfigured && sdkConfigured -> "configuration_locked"
        bridgeConfigured && !sdkConfigured -> "not_configured"
        else -> null
    }

    fun validStorageName(name: String): Boolean = name.matches(Regex("[a-z][a-z0-9_.-]{0,63}"))
    fun validStorageValue(value: String): Boolean = value.toByteArray(Charsets.UTF_8).size <= 16_384

    fun recoveryText(playerId: String, recoveryCode: String): String? {
        if (!playerId.matches(Regex("[A-Za-z0-9_-]{22}")) ||
            !recoveryCode.matches(Regex("[A-Za-z0-9_-]{43}"))) return null
        return "After You recovery details\nIdentity: $playerId\nRecovery code: $recoveryCode"
    }
}
