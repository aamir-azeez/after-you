package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class ExportFilesTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun keepsPlainNamesAndCleansTheRest() {
        assertEquals("relay-isles-attempt-1.afteryou", ExportFiles.safeName("relay-isles-attempt-1.afteryou"))
        assertEquals("relay-isles-attempt-1.afteryou", ExportFiles.safeName(" Relay Isles  attempt 1.afteryou "))
        assertEquals("etc-passwd", ExportFiles.safeName("../../etc/passwd"))
        assertNull(ExportFiles.safeName("..."))
        assertNull(ExportFiles.safeName(""))
        assertNull(ExportFiles.safeName("a".repeat(ExportFiles.MAX_NAME + 1)))
    }

    @Test fun mimeTypesFallBackToBytes() {
        assertEquals("application/octet-stream", ExportFiles.mimeType("application/octet-stream"))
        assertEquals("text/plain", ExportFiles.mimeType("text/plain"))
        assertEquals(ExportFiles.DEFAULT_MIME, ExportFiles.mimeType("text/plain; charset=utf-8"))
        assertEquals(ExportFiles.DEFAULT_MIME, ExportFiles.mimeType(""))
    }

    @Test fun writesTheOnlyFileInTheExportFolderAndOverwrites() {
        val cache = folder.newFolder("cache")
        val first = ExportFiles.write(cache, "first.afteryou", byteArrayOf(1, 2))!!
        assertEquals(File(File(cache, ExportFiles.DIRECTORY), "first.afteryou").canonicalPath, first.canonicalPath)
        val again = ExportFiles.write(cache, "second.afteryou", byteArrayOf(3))!!
        assertArrayEquals(byteArrayOf(3), again.readBytes())
        assertEquals(listOf("second.afteryou"), File(cache, ExportFiles.DIRECTORY).list()!!.toList())
        assertArrayEquals(byteArrayOf(4, 5), ExportFiles.write(cache, "second.afteryou", byteArrayOf(4, 5))!!.readBytes())
    }

    @Test fun refusesEmptyOversizeAndUnnamedFiles() {
        val cache = folder.newFolder("refused")
        assertNull(ExportFiles.write(cache, "empty.afteryou", ByteArray(0)))
        assertNull(ExportFiles.write(cache, "big.afteryou", ByteArray(HistoryFiles.MAX_BYTES + 1)))
        assertNull(ExportFiles.write(cache, "..", byteArrayOf(1)))
    }
}
