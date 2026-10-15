package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class BackupPolicyTest {
    @get:Rule val folder = TemporaryFolder()
    private val mb = 1024L * 1024

    private fun file(root: File, path: String, size: Int): File {
        val target = File(root, path)
        target.parentFile!!.mkdirs()
        target.writeBytes(ByteArray(size))
        return target
    }
    private fun plan(vararg paths: String) = (listOf(BackupPolicy.HEADER) + paths.map { "0\t$it" }).joinToString("\n")
    private fun names(root: File, files: List<File>) = files.map { it.relativeTo(root).invariantSeparatorsPath }

    @Test fun followsThePlanInOrderAndStopsBeforeTheQuotaMargin() {
        val root = folder.newFolder("files")
        file(root, "journey.json", 1000)
        file(root, "history/s/o/r/0-a.bin", 1000)
        file(root, "shared-replays/x.json", 1000)
        val chosen = BackupPolicy.select(root, plan("journey.json", "history/s/o/r/0-a.bin", "shared-replays/x.json"), BackupPolicy.MARGIN + 2 * BackupPolicy.cost(1000) + 10)
        assertEquals(listOf("journey.json", "history/s/o/r/0-a.bin"), names(root, chosen))
        assertEquals(emptyList<File>(), BackupPolicy.select(root, plan("journey.json"), BackupPolicy.MARGIN))
        assertEquals(3, BackupPolicy.select(root, plan("journey.json", "history/s/o/r/0-a.bin", "shared-replays/x.json"), 25 * mb).size)
    }

    @Test fun countsEachFilesTarOverheadSoManySmallFilesStillFit() {
        val root = folder.newFolder("many")
        val paths = (0 until 600).map { "history/aaaaaaaaaaaaaaaa/HHHHHHHHHHHHHHHHHHHHHH/RRRRRRRRRRRRRRRRRRRRRR/$it-0123456789abcdef.bin" }
        paths.forEach { file(root, it, 100) }
        val quota = BackupPolicy.MARGIN + 300 * BackupPolicy.cost(100)
        val chosen = BackupPolicy.select(root, plan(*paths.toTypedArray()), quota)
        assertEquals(300, chosen.size)
        // Raw sizes alone (60 KB) would have let all 600 through and pushed the real stream over the quota.
        assertTrue(chosen.sumOf { BackupPolicy.cost(it.length()) } <= quota - BackupPolicy.MARGIN)
    }

    @Test fun refusesPathsOutsideTheFilesDirectoryMissingFilesAndRepeats() {
        val root = folder.newFolder("app")
        file(root, "journey.json", 10)
        val outside = file(folder.root, "outside.json", 10)
        val chosen = BackupPolicy.select(root, plan("../outside.json", outside.absolutePath, "/journey.json", "a//b.json", "missing.json", "journey.json", "journey.json"), 25 * mb)
        assertEquals(listOf("journey.json"), names(root, chosen))
    }

    @Test fun fallsBackToSettingsAndJournalsWithoutAPlan() {
        val root = folder.newFolder("plain")
        file(root, "journey.json", 10)
        file(root, "relay-journey-v2.json", 10)
        file(root, "relay-journey-v2.json.backup", 10)
        file(root, "relay-online/x.json", 10)
        val expected = listOf("journey.json", "relay-journey-v2.json")
        assertEquals(expected, names(root, BackupPolicy.select(root, null, 25 * mb)))
        assertEquals(expected, names(root, BackupPolicy.select(root, "not a plan", 25 * mb)))
    }

    @Test fun sendsNothingToTheCloudWithoutClientSideEncryptionButAllowsPhoneToPhone() {
        assertFalse(BackupPolicy.allowed(0))
        assertTrue(BackupPolicy.allowed(BackupPolicy.CLIENT_SIDE_ENCRYPTION))
        assertTrue(BackupPolicy.allowed(BackupPolicy.DEVICE_TO_DEVICE))
        assertTrue(BackupPolicy.allowed(BackupPolicy.CLIENT_SIDE_ENCRYPTION or BackupPolicy.DEVICE_TO_DEVICE))
    }
}
