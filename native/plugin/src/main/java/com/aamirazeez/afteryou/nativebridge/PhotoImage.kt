package com.aamirazeez.afteryou.nativebridge

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

internal data class EncodedPhoto(val jpeg: ByteArray, val width: Int, val height: Int)

/** A worker-thread pixel decode/re-encode; original metadata and original bytes never leave here. */
internal object PhotoImage {
    fun sanitize(raw: File): EncodedPhoto {
        require(raw.isFile && raw.length() in 1..PhotoPolicy.MAX_RAW_BYTES)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(raw.path, bounds)
        require(PhotoPolicy.validDimensions(bounds.outWidth, bounds.outHeight))
        val options = BitmapFactory.Options().apply {
            inSampleSize = PhotoPolicy.decodeSample(bounds.outWidth, bounds.outHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = requireNotNull(BitmapFactory.decodeFile(raw.path, options))
        var oriented: Bitmap? = null
        try {
            val orientation = try {
                ExifInterface(raw.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
            val matrix = Matrix().apply {
                when (orientation) {
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                    ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
                }
            }
            oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            return encodePixels(oriented)
        } finally {
            if (oriented !== decoded) oriented?.recycle()
            decoded.recycle()
        }
    }

    private fun encodePixels(source: Bitmap): EncodedPhoto {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        for (maximumEdge in intArrayOf(PhotoAvatarPolicy.MAX_EDGE, 128, 96)) {
            val crop = PhotoAvatarPolicy.crop(source.width, source.height, maximumEdge)
            val edge = crop.outputEdge
            // Fresh ARGB pixels flatten transparency and omit source profiles and auxiliary metadata.
            // Crop oriented pixels, not the raw file: preview and retained bytes use this exact square.
            val flat = Bitmap.createBitmap(edge, edge, Bitmap.Config.ARGB_8888)
            try {
                Canvas(flat).apply {
                    drawColor(Color.WHITE)
                    drawBitmap(source, Rect(crop.left, crop.top, crop.left + crop.edge, crop.top + crop.edge), Rect(0, 0, edge, edge), paint)
                }
                var capped: EncodedPhoto? = null
                for (quality in intArrayOf(72, 60, 48, 36, 24)) {
                    val output = ByteArrayOutputStream()
                    check(flat.compress(Bitmap.CompressFormat.JPEG, quality, output))
                    // Android may add an APP2 color profile even to a fresh sRGB bitmap.
                    // Remove encoder metadata as well, then keep the strict JPEG release check.
                    val jpeg = PhotoPolicy.stripEncoderMetadata(output.toByteArray())
                    if (jpeg != null && jpeg.size <= PhotoAvatarPolicy.MAX_JPEG_BYTES) {
                        capped = EncodedPhoto(jpeg, edge, edge)
                        if (jpeg.size <= PhotoAvatarPolicy.TARGET_JPEG_BYTES) return capped
                    }
                }
                // The target is preferred; the smaller hard cap is mandatory for every new capture.
                if (capped != null) return capped
            } finally { flat.recycle() }
        }
        error("photo_size_limit")
    }
}
