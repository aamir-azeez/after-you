package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/** The Android backup rules keep out only what game/services/backup_plan.gd never sends. */
class BackupRulesTest {
    private val rules = File("src/main/res/xml/after_you_backup_rules.xml")
    private val legacy = File("src/main/res/xml/after_you_full_backup_rules.xml")
    private val plan = File("../../game/services/backup_plan.gd")

    private fun parse(file: File): Element = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement

    private fun excludes(parent: Element): List<String> {
        val nodes = parent.getElementsByTagName("exclude")
        return (0 until nodes.length).map { val e = nodes.item(it) as Element; e.getAttribute("domain") + ":" + e.getAttribute("path") }
    }

    @Test fun excludesOnlyAndTheSameEverywhere() {
        val modern = parse(rules)
        val old = parse(legacy)
        assertEquals("data-extraction-rules", modern.tagName)
        assertEquals("full-backup-content", old.tagName)
        assertEquals(0, modern.getElementsByTagName("include").length)
        assertEquals(0, old.getElementsByTagName("include").length)
        val cloud = modern.getElementsByTagName("cloud-backup").item(0) as Element
        val transfer = modern.getElementsByTagName("device-transfer").item(0) as Element
        assertEquals("true", cloud.getAttribute("disableIfNoEncryptionCapabilities"))
        val expected = excludes(old)
        assertTrue(expected.isNotEmpty())
        assertEquals(expected, excludes(cloud))
        assertEquals(expected, excludes(transfer))
    }

    @Test fun nothingThePlanSendsIsExcluded() {
        val source = plan.readText()
        val fixed = Regex("const FIXED := \\[([^\\]]*)\\]").find(source)!!.groupValues[1]
            .split(',').map { it.trim().trim('"') }.filter { it.isNotEmpty() }
        assertTrue(fixed.contains("journey.json"))
        val sent = fixed + listOf("history", "shared-replays", "turn-of-the-tide-journey-v2.json", "a.attempt-0a.json", "x-hard-runs.json")
        val excludedFiles = excludes(parse(legacy)).filter { it.startsWith("file:") }.map { it.removePrefix("file:") }
        assertFalse(excludedFiles.contains("."))
        for (path in sent) for (excluded in excludedFiles) {
            assertFalse("$excluded would drop $path", path == excluded || path.startsWith("$excluded/"))
        }
        // The plan's own "Never" list names these.
        for (folder in listOf("relay-online", "photo-transfer", "safety", "photo-library")) assertTrue(excludedFiles.contains(folder))
        // The root domain holds the files domain, so excluding it would drop every save on restore.
        assertFalse(excludes(parse(legacy)).any { it.startsWith("root:") || it.startsWith("device_root:") })
    }
}
