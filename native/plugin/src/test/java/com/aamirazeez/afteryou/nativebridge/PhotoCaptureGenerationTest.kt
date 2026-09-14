package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class PhotoCaptureGenerationTest {
    private fun state(): PhotoCaptureGeneration {
        var code = PhotoCameraRequestCodes.FIRST
        return PhotoCaptureGeneration { code++ }
    }

    @Test fun cancelledFlowCannotFinishOrDeliverCameraToReusedRequestId() {
        val state = state()
        val first = requireNotNull(state.begin("request"))
        val oldCamera = state.cameraRequest(first)
        assertNull(state.begin("another"))
        assertTrue(state.finish(first))
        val second = requireNotNull(state.begin("request"))
        val newCamera = state.cameraRequest(second)
        assertNotEquals(oldCamera, newCamera)
        assertNull(state.consumeCameraResult(oldCamera))
        assertFalse(state.isCurrent(first))
        assertFalse(state.finish(first))
        assertEquals(second, state.active)
        assertEquals(second, state.consumeCameraResult(newCamera))
        assertNull(state.consumeCameraResult(newCamera))
    }

    @Test fun retakeIgnoresDuplicateEarlierCameraReturn() {
        val state = state()
        val ticket = requireNotNull(state.begin("capture"))
        val first = state.cameraRequest(ticket)
        assertEquals(ticket, state.consumeCameraResult(first))
        val second = state.cameraRequest(ticket)
        assertNull(state.consumeCameraResult(first))
        assertEquals(second, state.cameraCode(ticket))
        assertEquals(ticket, state.consumeCameraResult(second))
        assertTrue(state.finish(ticket))
        assertNull(state.active)
    }

    @Test fun recreatedControllerCannotConsumeEarlierCameraResult() {
        var code = PhotoCameraRequestCodes.FIRST
        val reserve = { code++ }
        val old = PhotoCaptureGeneration(reserve)
        val first = requireNotNull(old.begin("same-request"))
        val oldCode = old.cameraRequest(first)
        // A different instance models controller recreation; its active state is deliberately empty.
        val current = PhotoCaptureGeneration(reserve)
        val second = requireNotNull(current.begin("same-request"))
        val nextCode = current.cameraRequest(second)
        assertNotEquals(oldCode, nextCode)
        assertNull(current.consumeCameraResult(oldCode))
        assertEquals(second, current.active)
        assertEquals(second, current.consumeCameraResult(nextCode))
    }

    @Test fun failedReservationDoesNotLeaveAnUndeliverableCameraRequest() {
        val current = PhotoCaptureGeneration { throw IllegalStateException("synthetic reservation failure") }
        val ticket = requireNotNull(current.begin("capture"))
        try { current.cameraRequest(ticket); fail("Reservation must fail") } catch (_: IllegalStateException) { }
        assertNull(current.cameraCode(ticket))
        assertTrue(current.finish(ticket))
        assertNotNull(current.begin("retry"))
    }
}
