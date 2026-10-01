package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class BridgePolicyTest {
    private val playerId = "player_0123456789"

    @Test fun releaseRejectsTestStoreAndNoBuildConfiguresTesterOnly() {
        listOf("test_placeholder", "goog_placeholder", "", "sk_placeholder").forEach { key ->
            assertEquals("unsupported_store", BridgePolicy.configError(key, playerId, "test_store"))
            assertEquals("unsupported_store", BridgePolicy.configError(key, playerId, "test_store", false))
            listOf(false, true).forEach { debug ->
                assertEquals("unsupported_store", BridgePolicy.configError(key, playerId, "tester_only", debug))
            }
        }
    }

    @Test fun acceptsOnlyMatchingPublicStoreKey() {
        listOf(false, true).forEach { debug ->
            assertNull(BridgePolicy.configError("goog_placeholder", playerId, "google_play", debug))
            assertEquals("store_key_mismatch", BridgePolicy.configError("test_placeholder", playerId, "google_play", debug))
        }
        assertNull(BridgePolicy.configError("test_placeholder", playerId, "test_store", true))
        assertEquals("store_key_mismatch", BridgePolicy.configError("goog_placeholder", playerId, "test_store", true))
    }

    @Test fun debugTestStoreStillRequiresExactModeAndCompletePublicConfiguration() {
        assertEquals("store_key_mismatch", BridgePolicy.configError("sk_placeholder", playerId, "test_store", true))
        assertEquals("store_key_mismatch", BridgePolicy.configError("TEST_placeholder", playerId, "test_store", true))
        assertEquals("unsupported_store", BridgePolicy.configError("test_placeholder", playerId, "TEST_STORE", true))
        assertEquals("invalid_player_id", BridgePolicy.configError("test_placeholder", "person@example.test", "test_store", true))
        listOf("", "test_short", "test_bad key!", "test_" + "x".repeat(252)).forEach { key ->
            assertEquals("invalid_public_key", BridgePolicy.configError(key, playerId, "test_store", true))
        }
    }

    @Test fun secretKeysAndUnimplementedStoresAreRejected() {
        assertEquals("store_key_mismatch", BridgePolicy.configError("sk_placeholder", playerId, "google_play"))
        assertEquals("unsupported_store", BridgePolicy.configError("galx_placeholder", playerId, "galaxy"))
    }

    @Test fun playerIdentityMustBeOpaqueAndConfigurationMustBeComplete() {
        assertEquals("invalid_player_id", BridgePolicy.configError("goog_placeholder", "person@example.test", "google_play"))
        assertEquals("invalid_public_key", BridgePolicy.configError("", playerId, "google_play"))
        assertEquals("invalid_public_key", BridgePolicy.configError("goog_bad key!", playerId, "google_play"))
    }

    @Test fun aRejectedStoreDoesNotPoisonLaterValidPlayConfiguration() {
        assertEquals("unsupported_store", BridgePolicy.configError("test_placeholder", playerId, "test_store"))
        assertNull(BridgePolicy.sdkStateError(false, false))
        assertNull(BridgePolicy.configError("goog_placeholder", playerId, "google_play"))
        assertNull(BridgePolicy.sdkStateError(true, true))
    }

    @Test fun preconfiguredSdkIsNeverRelabeledAsThisBridgesSession() {
        assertEquals("configuration_locked", BridgePolicy.sdkStateError(false, true))
        assertEquals("not_configured", BridgePolicy.sdkStateError(true, false))
    }

    @Test fun storagePathsAndSizesAreBounded() {
        assertTrue(BridgePolicy.validStorageName("device_token"))
        assertFalse(BridgePolicy.validStorageName("../device_token"))
        assertFalse(BridgePolicy.validStorageName("nested/token"))
        assertFalse(BridgePolicy.validStorageName(""))
        assertTrue(BridgePolicy.validStorageValue("x".repeat(16_384)))
        assertFalse(BridgePolicy.validStorageValue("x".repeat(16_385)))
        assertFalse(BridgePolicy.validStorageValue("€".repeat(6000)))
    }

    @Test fun recoveryCopyContainsExactlyTheTwoRecoveryFields() {
        val identity = "a".repeat(20) + "_-"
        val recovery = "Z".repeat(40) + "9_-"
        assertEquals("After You recovery details\nIdentity: $identity\nRecovery code: $recovery",
            BridgePolicy.recoveryText(identity, recovery))
    }

    @Test fun recoveryCopyRejectsWrongLengthsAndNonUrlSafeInput() {
        val identity = "i".repeat(22)
        val recovery = "r".repeat(43)
        listOf("", identity.dropLast(1), identity + "x", "i".repeat(21) + "=",
            "i".repeat(21) + "\n", "i".repeat(21) + " ", "i".repeat(21) + "é").forEach {
            assertNull(BridgePolicy.recoveryText(it, recovery))
        }
        listOf("", recovery.dropLast(1), recovery + "x", "r".repeat(42) + "+",
            "r".repeat(42) + "/", "r".repeat(42) + "\n", "r".repeat(42) + "=").forEach {
            assertNull(BridgePolicy.recoveryText(identity, it))
        }
    }
}
