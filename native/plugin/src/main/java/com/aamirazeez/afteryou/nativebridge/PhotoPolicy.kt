package com.aamirazeez.afteryou.nativebridge

import java.io.ByteArrayOutputStream

/** Bounds and file identifiers are independent of accounts, rooms and recordings. */
internal object PhotoPolicy {
    const val MAX_JPEG_BYTES = 160 * 1024
    const val MAX_RAW_BYTES = 32L * 1024 * 1024
    const val MAX_EDGE = 960
    const val MAX_FILES = 16
    const val EXPIRY_MS = 24L * 60 * 60 * 1000

    fun validId(id: String) = Regex("[a-f0-9]{32}").matches(id)

    fun validDimensions(width: Int, height: Int) =
        width in 1..24000 && height in 1..24000 && width.toLong() * height <= 200_000_000L

    fun decodeSample(width: Int, height: Int): Int {
        require(validDimensions(width, height))
        var sample = 1
        while (width / sample > MAX_EDGE * 2 || height / sample > MAX_EDGE * 2) sample *= 2
        return sample
    }

    /** Strip even profiles inserted by Android's fresh-pixel encoder; never used on raw camera data. */
    fun stripEncoderMetadata(data: ByteArray): ByteArray? {
        if (data.size < 4 || data.size > MAX_RAW_BYTES || u(data, 0) != 0xff || u(data, 1) != 0xd8) return null
        val output = ByteArrayOutputStream(minOf(data.size, MAX_JPEG_BYTES))
        output.write(data, 0, 2)
        var i = 2
        while (i + 3 < data.size) {
            if (u(data, i) != 0xff) return null
            val marker = u(data, i + 1)
            val length = u(data, i + 2) * 256 + u(data, i + 3)
            if (length < 2 || i + 2 + length > data.size) return null
            if (marker == 0xda) {
                output.write(data, i, data.size - i)
                return output.toByteArray().takeIf { safeJpeg(it) }
            }
            if (marker !in 0xe0..0xef && marker != 0xfe) {
                if (marker !in setOf(0xc0, 0xc4, 0xdb, 0xdd)) return null
                output.write(data, i, length + 2)
            }
            i += length + 2
        }
        return null
    }

    /** Accept only a complete baseline JPEG with no EXIF/XMP/IPTC/comments or trailing data. */
    fun safeJpeg(data: ByteArray): Boolean {
        if (data.size !in 4..MAX_JPEG_BYTES || u(data, 0) != 0xff || u(data, 1) != 0xd8) return false
        var i = 2
        var scan = false
        while (i < data.size) {
            if (scan) {
                if (u(data, i++) != 0xff) continue
                while (i < data.size && u(data, i) == 0xff) i++
                if (i >= data.size) return false
                val marker = u(data, i++)
                if (marker == 0x00 || marker in 0xd0..0xd7) continue
                return marker == 0xd9 && i == data.size
            }
            if (u(data, i++) != 0xff || i >= data.size) return false
            val marker = u(data, i++)
            // APP0/JFIF is codec framing. All other APP segments and comments are excluded.
            if (marker !in setOf(0xe0, 0xc0, 0xc4, 0xdb, 0xdd, 0xda)) return false
            if (i + 2 > data.size) return false
            val length = u(data, i) * 256 + u(data, i + 1)
            if (length < 2 || i + length > data.size) return false
            if (marker == 0xe0) {
                // The encoder's fixed JFIF header only: no APP0 extensions or embedded thumbnail.
                if (length != 16 || !data.copyOfRange(i + 2, i + 7).contentEquals(byteArrayOf(74, 70, 73, 70, 0))) return false
                if (u(data, i + 14) != 0 || u(data, i + 15) != 0) return false
            }
            i += length
            scan = marker == 0xda
        }
        return false
    }

    private fun u(data: ByteArray, index: Int) = data[index].toInt() and 0xff
}
