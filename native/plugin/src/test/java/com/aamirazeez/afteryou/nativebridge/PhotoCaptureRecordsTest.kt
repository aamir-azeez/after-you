package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class PhotoCaptureRecordsTest {
    private val pending = PendingCapture("0f1e2d3c4b5a69788796a5b4c3d2e1f0-12", PhotoCameraRequestCodes.FIRST + 9, "0123456789abcdef0123456789abcdef.jpg", 1_760_000_000_000L)
    private val metadata = "{\"status\":\"kept\",\"photo_id\":\"11111111111111111111111111111111\",\"uploaded\":false}"

    @Test fun pendingRecordRoundTripsAndNamesNoRoomOrTurn() {
        val bytes = PhotoCaptureRecords.encode(pending)
        assertEquals(pending, PhotoCaptureRecords.decodePending(bytes))
        val text = String(bytes, Charsets.UTF_8)
        assertFalse(text.contains("room") || text.contains("turn"))
    }

    @Test fun truncatedOrCorruptPendingRecordsReadAsNothing() {
        val bytes = PhotoCaptureRecords.encode(pending)
        for (size in 0 until bytes.size) assertNull(PhotoCaptureRecords.decodePending(bytes.copyOf(size)))
        assertNull(PhotoCaptureRecords.decodePending(null))
        assertNull(PhotoCaptureRecords.decodePending(String(bytes, Charsets.UTF_8).replace(".jpg", ".png").toByteArray()))
        assertNull(PhotoCaptureRecords.decodePending(String(bytes, Charsets.UTF_8).replace("16649", "99999").toByteArray()))
        assertNull(PhotoCaptureRecords.decodePending(ByteArray(PhotoCaptureRecords.MAX_BYTES + 1) { 'a'.code.toByte() }))
        assertNull(PhotoCaptureRecords.decodePending(byteArrayOf(-1, -2, 0, 10)))
    }

    @Test fun invalidPendingRecordsAreNeverWritten() {
        for (bad in listOf(pending.copy(requestId = "../x"), pending.copy(rawName = "photo.jpg"), pending.copy(requestCode = 1), pending.copy(startedWallMs = -1))) {
            try { PhotoCaptureRecords.encode(bad); fail("Invalid record must not encode: $bad") } catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun recoveredMarkRoundTripsAndRejectsDamage() {
        val record = RecoveredPhoto("capture-7", metadata)
        val bytes = PhotoCaptureRecords.encode(record)
        assertEquals(record, PhotoCaptureRecords.decodeRecovered(bytes))
        for (size in 0 until bytes.size) assertNull(PhotoCaptureRecords.decodeRecovered(bytes.copyOf(size)))
        assertNull(PhotoCaptureRecords.decodeRecovered(PhotoCaptureRecords.encode(pending)))
        try { PhotoCaptureRecords.encode(RecoveredPhoto("capture-7", "{\n}")); fail("A newline must not split the mark") } catch (_: IllegalArgumentException) { }
    }
}
