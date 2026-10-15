package com.aamirazeez.afteryou.nativebridge

/** Late camera/decode results cannot attach to a newer flow, even if a caller reuses an ID. */
internal class PhotoCaptureGeneration(private val reserveCameraCode: () -> Int) {
    data class Ticket(val requestId: String, val generation: Long)
    var active: Ticket? = null
        private set
    private var generation = 0L
    private var cameraCode: Int? = null
    /** Set when Android destroys the host. Nothing may close the camera after that. */
    var hostGone = false
        private set

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
    /** The camera to close for an explicit cancel; never one the host lost while it was open. */
    fun cancelCode(ticket: Ticket): Int? = if (hostGone) null else cameraCode(ticket)
    /**
     * The host is going away without the player asking. The camera keeps running and its result
     * reaches the recreated Activity through the persisted request, so no code is returned here.
     */
    fun hostDestroyed() { hostGone = true }
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
