package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class PhotoPolicyTest {
    private fun bytes(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private val scan = bytes(0xff, 0xd8, 0xff, 0xda, 0, 2, 10, 20, 0xff, 0, 30, 0xff, 0xd9)

    @Test fun identifiersCannotResolveArbitraryPaths() {
        assertTrue(PhotoPolicy.validId("ab".repeat(16)))
        for (id in listOf("../player_identity", "/data/local/tmp/photo", "a".repeat(31), "A".repeat(32), "0".repeat(32) + ".jpg", "")) {
            assertFalse(PhotoPolicy.validId(id))
        }
    }

    @Test fun decodedImageBoundsAvoidHugeUntrustedAllocations() {
        assertFalse(PhotoPolicy.validDimensions(0, 10))
        assertFalse(PhotoPolicy.validDimensions(Int.MAX_VALUE, Int.MAX_VALUE))
        assertFalse(PhotoPolicy.validDimensions(24000, 24000))
        assertTrue(PhotoPolicy.validDimensions(16000, 12000))
        for ((width, height) in listOf(1 to 1, 1600 to 1200, 12000 to 16000, 24000 to 1)) {
            val sample = PhotoPolicy.decodeSample(width, height)
            assertTrue(width / sample <= 1920 && height / sample <= 1920)
        }
    }

    @Test fun metadataSegmentsAndTrailingDataAreRejected() {
        assertTrue(PhotoPolicy.safeJpeg(scan))
        for (marker in 0xe1..0xef) {
            val withApp = bytes(0xff, 0xd8, 0xff, marker, 0, 6, 65, 66, 67, 68) + scan.drop(2).toByteArray()
            assertFalse(PhotoPolicy.safeJpeg(withApp))
        }
        assertFalse(PhotoPolicy.safeJpeg(bytes(0xff, 0xd8, 0xff, 0xfe, 0, 3, 65) + scan.drop(2).toByteArray()))
        assertFalse(PhotoPolicy.safeJpeg(scan + bytes(65)))
        assertFalse(PhotoPolicy.safeJpeg(scan.copyOf(scan.size - 1)))
        assertFalse(PhotoPolicy.safeJpeg(ByteArray(PhotoPolicy.MAX_JPEG_BYTES + 1)))
        for (length in 0 until scan.size - 1) assertFalse(PhotoPolicy.safeJpeg(scan.copyOf(length)))
    }

    @Test fun freshEncoderMetadataIsRemovedWithoutRelaxingReleaseValidation() {
        for (marker in (0xe0..0xef).toList() + 0xfe) {
            val withMetadata = bytes(0xff, 0xd8, 0xff, marker, 0, 6, 65, 66, 67, 68) + scan.drop(2).toByteArray()
            assertArrayEquals(scan, PhotoPolicy.stripEncoderMetadata(withMetadata))
        }
        assertNull(PhotoPolicy.stripEncoderMetadata(scan + bytes(65)))
        assertNull(PhotoPolicy.stripEncoderMetadata(bytes(0xff, 0xd8, 0xff, 0xe2, 127, 127, 65)))
        assertNull(PhotoPolicy.stripEncoderMetadata(bytes(0xff, 0xd8, 0xff, 0xc2, 0, 2) + scan.drop(2).toByteArray()))
    }
}
