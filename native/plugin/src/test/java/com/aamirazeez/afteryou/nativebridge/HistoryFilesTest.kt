package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class HistoryFilesTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun writesCreatesDirectoriesAndReplacesWithoutLeavingATemporaryFile() {
        val root = folder.newFolder("files")
        val target = File(root, "history/server/owner/room/0-abcdef.bin")
        assertTrue(HistoryFiles.write(target, byteArrayOf(1, 2, 3)))
        assertArrayEquals(byteArrayOf(1, 2, 3), target.readBytes())
        assertTrue(HistoryFiles.write(target, byteArrayOf(9)))
        assertArrayEquals(byteArrayOf(9), target.readBytes())
        assertFalse(File(target.parentFile, target.name + ".new").exists())
    }

    @Test fun refusesOversizeBodiesAndKeepsTheOldFile() {
        val target = File(folder.newFolder("big"), "a.bin")
        assertTrue(HistoryFiles.write(target, byteArrayOf(7)))
        assertFalse(HistoryFiles.write(target, ByteArray(HistoryFiles.MAX_BYTES + 1)))
        assertArrayEquals(byteArrayOf(7), target.readBytes())
    }

    @Test fun allowsOnlyPathsInsideTheFilesDirectory() {
        val root = folder.newFolder("app")
        assertTrue(HistoryFiles.allowed(root, File(root, "history/x.bin")))
        assertFalse(HistoryFiles.allowed(root, File(root, "../outside.bin")))
        assertFalse(HistoryFiles.allowed(root, File(folder.root, "outside.bin")))
        assertFalse(HistoryFiles.allowed(root, root))
    }

    @Test fun failsWhenTheParentCannotBeCreated() {
        val blocker = folder.newFile("blocker")
        assertFalse(HistoryFiles.write(File(blocker, "child/a.bin"), byteArrayOf(1)))
    }
}
