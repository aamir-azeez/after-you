package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class BridgePolicyTest {
    private val playerId = "player_0123456789"

    @Test fun testStoreRequiresDebuggableApplication() {
        assertEquals("test_store_requires_debug_build", BridgePolicy.buildError("test_store", false))
        assertNull(BridgePolicy.buildError("test_store", true))
        assertNull(BridgePolicy.buildError("google_play", false))
    }

    @Test fun acceptsOnlyMatchingPublicStoreKey() {
        assertNull(BridgePolicy.configError("test_placeholder", playerId, "test_store"))
        assertNull(BridgePolicy.configError("goog_placeholder", playerId, "google_play"))
        assertEquals("store_key_mismatch", BridgePolicy.configError("goog_placeholder", playerId, "test_store"))
        assertEquals("store_key_mismatch", BridgePolicy.configError("test_placeholder", playerId, "google_play"))
    }

    @Test fun secretKeysAndUnimplementedStoresAreRejected() {
        assertEquals("store_key_mismatch", BridgePolicy.configError("sk_placeholder", playerId, "test_store"))
        assertEquals("unsupported_store", BridgePolicy.configError("galx_placeholder", playerId, "galaxy"))
    }

    @Test fun playerIdentityMustBeOpaqueAndConfigurationMustBeComplete() {
        assertEquals("invalid_player_id", BridgePolicy.configError("test_placeholder", "person@example.test", "test_store"))
        assertEquals("invalid_public_key", BridgePolicy.configError("", playerId, "test_store"))
        assertEquals("invalid_public_key", BridgePolicy.configError("test_bad key!", playerId, "test_store"))
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
}
