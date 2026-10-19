package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class PlayGamesPolicyTest {
    @Test fun onlyANumericProjectIdTurnsPlayGamesOn() {
        assertTrue(PlayGamesPolicy.configured("123456789012"))
        assertFalse(PlayGamesPolicy.configured(""))
        assertFalse(PlayGamesPolicy.configured(null))
        assertFalse(PlayGamesPolicy.configured("12345"))
        assertFalse(PlayGamesPolicy.configured("1234567890123456789012"))
        assertFalse(PlayGamesPolicy.configured("12345678901a"))
        assertFalse(PlayGamesPolicy.configured(" 123456789012"))
    }

    @Test fun serverAuthCodesAreRequestedOnlyForAWebClientId() {
        assertTrue(PlayGamesPolicy.validWebClientId("123456789012-syntheticclientabc.apps.googleusercontent.com"))
        assertFalse(PlayGamesPolicy.validWebClientId("123456789012-syntheticclientabc.apps.googleusercontent.com.evil.test"))
        assertFalse(PlayGamesPolicy.validWebClientId("synthetic-client"))
        assertFalse(PlayGamesPolicy.validWebClientId(""))
    }

    @Test fun thePlayerKeyIsOneWayStableAndDistinct() {
        val key = PlayGamesPolicy.playerKey("g12345678901234567890")
        assertTrue(key.matches(Regex("[a-f0-9]{64}")))
        assertEquals(key, PlayGamesPolicy.playerKey("g12345678901234567890"))
        assertNotEquals(key, PlayGamesPolicy.playerKey("g12345678901234567891"))
        assertFalse(key.contains("12345678901234567890"))
    }

    @Test fun sdkStatusCodesBecomeTheGamesFewCodes() {
        assertEquals("signed_out", PlayGamesPolicy.errorCode(4))
        assertEquals("offline", PlayGamesPolicy.errorCode(7))
        assertEquals("cancelled", PlayGamesPolicy.errorCode(16))
        assertEquals("cancelled", PlayGamesPolicy.errorCode(12501))
        assertEquals("timeout", PlayGamesPolicy.errorCode(15))
        assertEquals("unavailable", PlayGamesPolicy.errorCode(1))
        assertEquals("unavailable", PlayGamesPolicy.errorCode(9))
        assertEquals("not_configured", PlayGamesPolicy.errorCode(10))
        assertEquals("failed", PlayGamesPolicy.errorCode(null))
        assertEquals("failed", PlayGamesPolicy.errorCode(99999))
    }

    @Test fun requestShapesAreBounded() {
        assertTrue(PlayGamesPolicy.validSnapshotName("after-you-progress"))
        assertFalse(PlayGamesPolicy.validSnapshotName("../after-you"))
        assertFalse(PlayGamesPolicy.validSnapshotName("A" + "a".repeat(10)))
        assertFalse(PlayGamesPolicy.validSnapshotName("a".repeat(65)))
        assertTrue(PlayGamesPolicy.validHandle("0".repeat(32)))
        assertFalse(PlayGamesPolicy.validHandle("0".repeat(31)))
        assertTrue(PlayGamesPolicy.validDescription("After You progress"))
        assertFalse(PlayGamesPolicy.validDescription("x".repeat(101)))
        assertFalse(PlayGamesPolicy.validDescription("line\nbreak"))
        assertTrue(PlayGamesPolicy.validBase64Length("A".repeat(PlayGamesPolicy.MAX_SNAPSHOT_BASE64)))
        assertFalse(PlayGamesPolicy.validBase64Length("A".repeat(PlayGamesPolicy.MAX_SNAPSHOT_BASE64 + 1)))
        assertTrue(PlayGamesPolicy.QUIET_TIMEOUT_MS < 15_000 && PlayGamesPolicy.SNAPSHOT_TIMEOUT_MS < 30_000 && PlayGamesPolicy.SIGN_IN_TIMEOUT_MS < 120_000)
    }

    @Test fun handlesAreRandomBoundedAndTakenOnce() {
        val handle = PlayGamesPolicy.newHandle()
        assertTrue(PlayGamesPolicy.validHandle(handle))
        assertNotEquals(handle, PlayGamesPolicy.newHandle())
        val book = SnapshotHandles<String>(max = 2)
        val first = book.put("slot-a")!!
        val second = book.put("slot-b")!!
        assertNull(book.put("slot-c"))
        assertEquals("slot-a", book.get(first))
        assertEquals("slot-a", book.take(first))
        assertNull(book.take(first))
        assertNotNull(book.put("slot-c"))
        assertEquals(listOf("slot-b", "slot-c"), book.drain())
        assertEquals(0, book.size())
        assertNull(book.get(second))
    }

    @Test fun aRepeatedHandleIsNeverHandedOutTwice() {
        val values = ArrayDeque(listOf("a".repeat(32), "a".repeat(32), "b".repeat(32)))
        val book = SnapshotHandles<Int>(max = 2) { values.removeFirst() }
        assertEquals("a".repeat(32), book.put(1))
        assertEquals("b".repeat(32), book.put(2))
    }
}
