package com.aamirazeez.afteryou.nativebridge

/** New captures are small avatars. Historical cache/network read limits stay in PhotoPolicy. */
internal object PhotoAvatarPolicy {
    const val MAX_EDGE = 160
    const val TARGET_JPEG_BYTES = 10 * 1024
    const val MAX_JPEG_BYTES = 24 * 1024

    data class Crop(val left: Int, val top: Int, val edge: Int, val outputEdge: Int)

    /** Called after applying EXIF orientation. Odd margins differ by at most one pixel. */
    fun crop(width: Int, height: Int, maximumEdge: Int = MAX_EDGE): Crop {
        require(PhotoPolicy.validDimensions(width, height))
        require(maximumEdge in 1..MAX_EDGE)
        val edge = minOf(width, height)
        return Crop((width - edge) / 2, (height - edge) / 2, edge, minOf(edge, maximumEdge))
    }
}
