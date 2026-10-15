package com.aamirazeez.afteryou.nativebridge

import com.aamirazeez.afteryou.nativebridge.PhotoCaptureRecoveryPolicy.Decision
import com.aamirazeez.afteryou.nativebridge.PhotoCaptureRecoveryPolicy.Live
import org.junit.Assert.*
import org.junit.Test

class PhotoCaptureRecoveryPolicyTest {
    private val record = PendingCapture("capture-1", PhotoCameraRequestCodes.FIRST, "0123456789abcdef0123456789abcdef.jpg", 1_000L)
    private val ok = -1
    private val canceled = 0

    @Test fun writtenPhotoIsRecoveredWhateverTheResultCode() {
        for (code in listOf(null, ok, canceled, 7)) {
            assertEquals(Decision.RECOVER, PhotoCaptureRecoveryPolicy.decide(record, true, 2048, 60_000, code))
        }
    }

    @Test fun emptyOutputWaitsForALateResultThenIsRemoved() {
        assertEquals(Decision.WAIT, PhotoCaptureRecoveryPolicy.decide(record, true, 0, 5_000, null))
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(record, true, 0, 5_000, canceled))
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(record, true, 0, 5_000, ok))
    }

    @Test fun missingStaleOrUnrecordedOutputIsRemoved() {
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(null, true, 2048, 5_000, null))
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(record, false, 0, 5_000, ok))
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(record, true, 2048, PhotoCaptureRecoveryPolicy.MAX_AGE_MS + 1, null))
        assertEquals(Decision.DISCARD, PhotoCaptureRecoveryPolicy.decide(record, true, 2048, -10 * 60_000L, null))
        assertEquals(Decision.RECOVER, PhotoCaptureRecoveryPolicy.decide(record, true, 2048, -5_000L, null))
    }

    @Test fun liveResultSkipsOnlyOnAnExplicitCancelWithNoPhoto() {
        assertEquals(Live.KEEP, PhotoCaptureRecoveryPolicy.live(4096, ok))
        assertEquals(Live.KEEP, PhotoCaptureRecoveryPolicy.live(4096, canceled))
        assertEquals(Live.KEEP, PhotoCaptureRecoveryPolicy.live(4096, 3))
        assertEquals(Live.SKIP, PhotoCaptureRecoveryPolicy.live(0, canceled))
        assertEquals(Live.FAIL, PhotoCaptureRecoveryPolicy.live(0, ok))
        assertEquals(Live.FAIL, PhotoCaptureRecoveryPolicy.live(0, 3))
    }
}
