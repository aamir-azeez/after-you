package com.aamirazeez.afteryou.nativebridge

/** Late camera/decode results cannot attach to a newer flow, even if a caller reuses an ID. */
internal class PhotoCaptureGeneration(private val reserveCameraCode: () -> Int) {
    data class Ticket(val requestId: String, val generation: Long)
    var active: Ticket? = null
        private set
    private var generation = 0L
    private var cameraCode: Int? = null

    fun begin(id: String): Ticket? {
        if (active != null) return null
        return Ticket(id, ++generation).also { active = it }
    }
    fun isCurrent(ticket: Ticket) = active == ticket
    fun cameraRequest(ticket: Ticket): Int {
        check(isCurrent(ticket) && cameraCode == null)
        val code = reserveCameraCode()
        check(code in PhotoCameraRequestCodes.FIRST..PhotoCameraRequestCodes.LAST)
        cameraCode = code
        return code
    }
    fun cameraCode(ticket: Ticket): Int? = if (isCurrent(ticket)) cameraCode else null
    fun consumeCameraResult(code: Int): Ticket? {
        if (code != cameraCode) return null
        cameraCode = null
        return active
    }
    fun finish(ticket: Ticket): Boolean {
        if (!isCurrent(ticket)) return false
        active = null
        cameraCode = null
        return true
    }
}
