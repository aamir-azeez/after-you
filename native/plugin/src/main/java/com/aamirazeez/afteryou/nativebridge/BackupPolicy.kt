package com.aamirazeez.afteryou.nativebridge

import java.io.File
import java.io.IOException

/**
 * What goes into this phone's Android backup. The game writes the plan
 * (`backup-plan.txt` in its files directory, rebuilt as its files change) in
 * priority order; this keeps the files that fit the transport's quota, leaving a
 * margin, so the backup never grows past the limit where Android skips it whole.
 */
object BackupPolicy {
    const val PLAN = "backup-plan.txt"
    const val HEADER = "after-you-backup-plan 1"
    const val MARGIN = 2L * 1024 * 1024
    const val MAX_PLAN_BYTES = 512 * 1024
    const val MAX_ENTRIES = 4096
    /** BackupAgent.FLAG_CLIENT_SIDE_ENCRYPTION_ENABLED and FLAG_DEVICE_TO_DEVICE_TRANSFER (API 28). */
    const val CLIENT_SIDE_ENCRYPTION = 1
    const val DEVICE_TO_DEVICE = 2
    /** Settings and progress, used when the plan is missing or unreadable. */
    private val FIXED = listOf("journey.json", "home-keepsakes-v1.json", "solo-replay-visibility.json")
    private val JOURNAL = Regex("^[a-z0-9-]+-journey-v[0-9]+\\.json$")

    /** Cloud backups only when they are end-to-end encrypted; a cable or Wi-Fi transfer to a new phone always. */
    fun allowed(transportFlags: Int): Boolean = transportFlags and (CLIENT_SIDE_ENCRYPTION or DEVICE_TO_DEVICE) != 0

    fun select(root: File, plan: String?, quota: Long): List<File> {
        val budget = quota - MARGIN
        if (budget <= 0) return emptyList()
        val candidates = parse(root, plan) ?: fallback(root)
        val chosen = mutableListOf<File>()
        var total = 0L
        for (file in candidates) {
            val size = file.length()
            if (total + size > budget) break
            chosen.add(file)
            total += size
        }
        return chosen
    }

    /** Files named by the plan that exist inside root, in plan order; null when there is no usable plan. */
    private fun parse(root: File, plan: String?): List<File>? {
        if (plan == null || plan.length > MAX_PLAN_BYTES) return null
        val lines = plan.split('\n').map { it.trimEnd('\r') }
        if (lines.firstOrNull() != HEADER) return null
        val seen = HashSet<String>()
        return lines.drop(1).filter { it.isNotEmpty() }.take(MAX_ENTRIES).mapNotNull { line ->
            val path = line.substringAfter('\t', "")
            val file = File(root, path)
            if (path.isEmpty() || path.startsWith("/") || path.split('/').any { it == ".." || it.isEmpty() } || !inside(root, file) || !file.isFile || !seen.add(file.path)) null else file
        }
    }

    private fun fallback(root: File): List<File> {
        val fixed = FIXED.map { File(root, it) }.filter { it.isFile }
        val journals = root.listFiles()?.filter { it.isFile && JOURNAL.matches(it.name) }?.sortedBy { it.name } ?: emptyList()
        return fixed + journals
    }

    private fun inside(root: File, file: File): Boolean = try {
        file.canonicalPath.startsWith(root.canonicalPath + File.separator)
    } catch (_: IOException) {
        false
    }
}
