package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException

/**
 * A camera request that may outlive this Activity or process. It names only the caller's opaque
 * request ID, the reserved camera code and the raw output file: never a room, turn or account.
 */
internal data class PendingCapture(val requestId: String, val requestCode: Int, val rawName: String, val startedWallMs: Long)

/** A sanitized photo kept in [PhotoCache] that no turn journal has adopted yet. */
internal data class RecoveredPhoto(val requestId: String, val metadataJson: String)

/** Plain text codecs, so the JVM tests need no Android or org.json stubs. */
internal object PhotoCaptureRecords {
    private const val PENDING_VERSION = "after-you-pending-capture-v1"
    private const val RECOVERED_VERSION = "after-you-recovered-photo-v1"
    const val MAX_BYTES = 4096
    /** A torn write cannot end with this line, so truncation never decodes as a shorter value. */
    private const val END = "end"
    private val requestPattern = Regex("[A-Za-z0-9_-]{1,80}")
    private val rawPattern = Regex("[a-f0-9]{32}\\.jpg")

    fun validRequestId(value: String) = requestPattern.matches(value)
    fun validRawName(value: String) = rawPattern.matches(value)

    fun encode(record: PendingCapture): ByteArray {
        require(validRequestId(record.requestId) && validRawName(record.rawName) && record.startedWallMs >= 0)
        require(record.requestCode in PhotoCameraRequestCodes.FIRST..PhotoCameraRequestCodes.LAST)
        return listOf(PENDING_VERSION, record.requestId, record.requestCode.toString(), record.rawName, record.startedWallMs.toString(), END)
            .joinToString("\n").toByteArray(Charsets.UTF_8)
    }

    fun decodePending(bytes: ByteArray?): PendingCapture? = try {
        val lines = text(bytes)?.split("\n")
        if (lines == null || lines.size != 6 || lines[0] != PENDING_VERSION || lines[5] != END) null else {
            val code = lines[2].toInt()
            val started = lines[4].toLong()
            if (!validRequestId(lines[1]) || !validRawName(lines[3]) || started < 0 ||
                code !in PhotoCameraRequestCodes.FIRST..PhotoCameraRequestCodes.LAST) null
            else PendingCapture(lines[1], code, lines[3], started)
        }
    } catch (_: Exception) { null }

    fun encode(record: RecoveredPhoto): ByteArray {
        require(validRequestId(record.requestId) && record.metadataJson.isNotEmpty() && '\n' !in record.metadataJson)
        val bytes = (RECOVERED_VERSION + "\n" + record.requestId + "\n" + record.metadataJson + "\n" + END).toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES)
        return bytes
    }

    fun decodeRecovered(bytes: ByteArray?): RecoveredPhoto? = try {
        val lines = text(bytes)?.split("\n")
        if (lines == null || lines.size != 4 || lines[0] != RECOVERED_VERSION || lines[3] != END || !validRequestId(lines[1]) ||
            !lines[2].startsWith("{") || !lines[2].endsWith("}")) null
        else RecoveredPhoto(lines[1], lines[2])
    } catch (_: Exception) { null }

    private fun text(bytes: ByteArray?): String? =
        if (bytes == null || bytes.isEmpty() || bytes.size > MAX_BYTES) null else String(bytes, Charsets.UTF_8)
}

/** What to do with a camera output found after the flow that asked for it was lost. */
internal object PhotoCaptureRecoveryPolicy {
    enum class Decision { RECOVER, WAIT, DISCARD }
    enum class Live { KEEP, SKIP, FAIL }
    const val MAX_AGE_MS = 30L * 60L * 1000L
    /** Wall clocks can step back a little; a record from far in the future is not trusted. */
    private const val CLOCK_SLACK_MS = 60L * 1000L
    private const val RESULT_CANCELED = 0

    /**
     * The file decides, not the result code: some cameras report CANCELED or odd codes after they
     * wrote the photo. resultCode is null when no camera result arrived (Activity or process start).
     */
    fun decide(record: PendingCapture?, fileExists: Boolean, fileSize: Long, ageMs: Long, resultCode: Int?): Decision {
        if (record == null || !fileExists || ageMs < -CLOCK_SLACK_MS || ageMs > MAX_AGE_MS) return Decision.DISCARD
        if (fileSize > 0) return Decision.RECOVER
        // An empty file with no result yet: the camera may still be open. Keep the grant for it.
        return if (resultCode == null) Decision.WAIT else Decision.DISCARD
    }

    /** A result for the live flow. Only an empty output with an explicit cancel is a Skip. */
    fun live(fileSize: Long, resultCode: Int): Live = when {
        fileSize > 0 -> Live.KEEP
        resultCode == RESULT_CANCELED -> Live.SKIP
        else -> Live.FAIL
    }
}

internal interface PendingCaptureStore {
    fun write(record: PendingCapture)
    fun read(): PendingCapture?
    fun clear()
}

internal interface RecoveredPhotoStore {
    fun write(record: RecoveredPhoto)
    fun read(): RecoveredPhoto?
    fun clear()
}

/** Small atomic files in noBackupFilesDir: never in a cloud backup, never in a shared cache. */
private class RecordFile(context: Context, name: String) {
    private val file = AtomicFile(File(context.noBackupFilesDir, name))

    @Synchronized fun write(bytes: ByteArray) {
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (e: Exception) {
            file.failWrite(stream)
            throw e
        }
    }

    @Synchronized fun read(): ByteArray? = try {
        file.openRead().use { input ->
            val bounded = ByteArray(PhotoCaptureRecords.MAX_BYTES + 1)
            var size = 0
            while (size < bounded.size) {
                val read = input.read(bounded, size, bounded.size - size)
                if (read < 0) break
                size += read
            }
            bounded.copyOf(size)
        }
    } catch (_: FileNotFoundException) { null
    } catch (_: Exception) { null }

    @Synchronized fun clear() = file.delete()
}

internal class PhotoPendingCapture(context: Context) : PendingCaptureStore {
    private val record = RecordFile(context, "after-you-photo-pending-capture")
    override fun write(record: PendingCapture) = this.record.write(PhotoCaptureRecords.encode(record))
    override fun read(): PendingCapture? = PhotoCaptureRecords.decodePending(record.read())
    override fun clear() = record.clear()
}

internal class PhotoRecoveredMarker(context: Context) : RecoveredPhotoStore {
    private val record = RecordFile(context, "after-you-photo-recovered")
    override fun write(record: RecoveredPhoto) = this.record.write(PhotoCaptureRecords.encode(record))
    override fun read(): RecoveredPhoto? = PhotoCaptureRecords.decodeRecovered(record.read())
    override fun clear() = record.clear()
}
