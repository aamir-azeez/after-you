package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class PhotoAvatarPolicyTest {
    @Test fun landscapeAndPortraitKeepOnlyTheCenteredSquare() {
        assertEquals(PhotoAvatarPolicy.Crop(200, 0, 1200, 160), PhotoAvatarPolicy.crop(1600, 1200))
        assertEquals(PhotoAvatarPolicy.Crop(0, 200, 1200, 160), PhotoAvatarPolicy.crop(1200, 1600))
        assertEquals(PhotoAvatarPolicy.Crop(0, 0, 160, 160), PhotoAvatarPolicy.crop(160, 160))
        assertEquals(PhotoAvatarPolicy.Crop(10, 0, 31, 31), PhotoAvatarPolicy.crop(52, 31))
    }

    @Test fun smallAndVeryNarrowInputsAreNotUpscaled() {
        for ((width, height) in listOf(40 to 30, 30 to 40, 1 to 24000, 24000 to 1, 159 to 159)) {
            val crop = PhotoAvatarPolicy.crop(width, height)
            assertTrue(crop.outputEdge <= minOf(width, height))
            assertTrue(crop.outputEdge in 1..160)
            assertTrue(crop.left >= 0 && crop.top >= 0)
            assertTrue(crop.left + crop.edge <= width && crop.top + crop.edge <= height)
            assertTrue(kotlin.math.abs(crop.left - (width - crop.left - crop.edge)) <= 1)
            assertTrue(kotlin.math.abs(crop.top - (height - crop.top - crop.edge)) <= 1)
        }
    }

    @Test fun impossibleDimensionsAndOversizedOutputAreRejected() {
        for ((width, height) in listOf(0 to 30, 30 to -1, 24000 to 24000, Int.MAX_VALUE to 1)) {
            try { PhotoAvatarPolicy.crop(width, height); fail("Invalid crop dimensions accepted") }
            catch (_: IllegalArgumentException) { }
        }
        for (edge in listOf(0, -1, 161)) {
            try { PhotoAvatarPolicy.crop(200, 200, edge); fail("Invalid avatar edge accepted") }
            catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun newCaptureBudgetDoesNotTightenHistoricalReadLimits() {
        assertEquals(160, PhotoAvatarPolicy.MAX_EDGE)
        assertEquals(24 * 1024, PhotoAvatarPolicy.MAX_JPEG_BYTES)
        assertEquals(10 * 1024, PhotoAvatarPolicy.TARGET_JPEG_BYTES)
        assertEquals(960, PhotoPolicy.MAX_EDGE)
        assertEquals(160 * 1024, PhotoPolicy.MAX_JPEG_BYTES)
    }
}
