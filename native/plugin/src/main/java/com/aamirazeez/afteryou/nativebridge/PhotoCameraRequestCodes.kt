package com.aamirazeez.afteryou.nativebridge

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.nio.ByteBuffer

/** Reserve before launch, so an old result cannot match a new capture after Activity/process death. */
internal class PhotoCameraRequestCodes(context: Context) {
    private val state = AtomicFile(File(context.noBackupFilesDir, "after-you-photo-request-code"))

    fun reserve(): Int = synchronized(lock) {
        val bytes = try {
            state.openRead().use { input ->
                val bounded = ByteArray(5)
                var size = 0
                while (size < bounded.size) {
                    val read = input.read(bounded, size, bounded.size - size)
                    if (read < 0) break
                    check(read > 0)
                    size += read
                }
                bounded.copyOf(size)
            }
        } catch (_: FileNotFoundException) { null }
        val code = if (bytes == null) FIRST else {
            check(bytes.size == 4)
            ByteBuffer.wrap(bytes).int
        }
        check(code in FIRST..LAST) // Never wrap and accidentally accept a stale result.
        val stream = state.startWrite()
        try {
            stream.write(ByteBuffer.allocate(4).putInt(code + 1).array())
            state.finishWrite(stream)
        } catch (e: Exception) {
            state.failWrite(stream)
            throw e
        }
        code
    }

    companion object {
        const val FIRST = 0x4100
        const val LAST = 0x7fff
        private val lock = Any()
    }
}
