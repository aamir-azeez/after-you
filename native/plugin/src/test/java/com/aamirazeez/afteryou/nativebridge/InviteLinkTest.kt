package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class InviteLinkTest {
    private val id = "Ab9_-" + "x".repeat(16) + "Z"
    private val fragment = "https://aamirazeez.com/after-you/link#friend-$id"
    private val query = "https://aamirazeez.com/after-you/link?c=friend-$id"

    @Test fun acceptsOnlyTheAgreedFragmentAndQueryForms() {
        listOf(fragment, query, "https://aamirazeez.com/after-you/link/#friend-$id",
            "https://aamirazeez.com/after-you/link/?c=friend-$id", "HTTPS://AamirAzeez.COM/after-you/link#friend-$id").forEach {
            assertTrue(it, InviteLinkPolicy.valid(it))
            assertEquals(it, InviteLinkPolicy.accept(InviteLinkPolicy.VIEW, it, false, false))
        }
    }

    @Test fun rejectsOtherSchemesHostsPathsAndShapes() {
        listOf(
            null, "", "http://aamirazeez.com/after-you/link#friend-$id",
            "https://www.aamirazeez.com/after-you/link#friend-$id", "https://aamirazeez.com.evil.test/after-you/link#friend-$id",
            "https://evil.test/https://aamirazeez.com/after-you/link#friend-$id", "https://user@aamirazeez.com/after-you/link#friend-$id",
            "https://aamirazeez.com:443/after-you/link#friend-$id", "https://aamirazeez.com/after-you#friend-$id",
            "https://aamirazeez.com/after-you/#friend-$id", "https://aamirazeez.com/after-you/linked#friend-$id",
            "https://aamirazeez.com/after-you/link/extra#friend-$id", "https://aamirazeez.com/After-You/link#friend-$id",
            "https://aamirazeez.com/after-you/link#$id", "https://aamirazeez.com/after-you/link#Friend-$id",
            "https://aamirazeez.com/after-you/link#room-0123456789ABCDEF0123", "https://aamirazeez.com/after-you/link#friend-${id.dropLast(1)}",
            "https://aamirazeez.com/after-you/link#friend-${id}x", "https://aamirazeez.com/after-you/link#friend-${id.dropLast(1)}=",
            "https://aamirazeez.com/after-you/link#friend-${id.dropLast(1)}%",
            "https://aamirazeez.com/after-you/link?c=friend-$id#friend-$id", "https://aamirazeez.com/after-you/link?c=friend-$id&x=1",
            "https://aamirazeez.com/after-you/link?x=1&c=friend-$id", "https://aamirazeez.com/after-you/link?code=friend-$id",
            "$fragment\n", " $fragment", "$fragment ", "https://aamirazeez.com/after-you/link#friend-" + "é".repeat(22),
            fragment + "x".repeat(300)
        ).forEach {
            assertFalse(it.toString(), InviteLinkPolicy.valid(it))
            assertEquals(InviteLinkPolicy.INVALID, InviteLinkPolicy.accept(InviteLinkPolicy.VIEW, it, false, false))
        }
    }

    @Test fun onlyFreshViewIntentsAreDelivered() {
        assertNull(InviteLinkPolicy.accept("android.intent.action.MAIN", fragment, false, false))
        assertNull(InviteLinkPolicy.accept(null, fragment, false, false))
        assertNull(InviteLinkPolicy.accept(InviteLinkPolicy.VIEW, fragment, true, false))
        assertNull(InviteLinkPolicy.accept(InviteLinkPolicy.VIEW, fragment, false, true))
    }

    @Test fun inboxDeliversEachLinkOnceAndKeepsOnlyTheNewest() {
        val inbox = InviteLinkInbox()
        assertEquals("", inbox.take())
        inbox.offer(fragment)
        assertTrue(inbox.hasPending())
        assertEquals(fragment, inbox.take())
        assertEquals("", inbox.take())
        assertFalse(inbox.hasPending())
        inbox.offer(fragment)
        inbox.offer(query)
        assertEquals(query, inbox.take())
        assertEquals("", inbox.take())
        inbox.offer(InviteLinkPolicy.INVALID)
        assertEquals(InviteLinkPolicy.INVALID, inbox.take())
        inbox.offer("https://evil.test/#friend-$id")
        assertFalse(inbox.hasPending())
        assertEquals("", inbox.take())
    }

    @Test fun listenerIsAHintForWarmDeliveryAndDetachStopsIt() {
        val inbox = InviteLinkInbox()
        var hints = 0
        val listener = InviteLinkListener { hints += 1 }
        inbox.offer(fragment)
        assertEquals(0, hints)
        inbox.attach(listener)
        inbox.offer(query)
        assertEquals(1, hints)
        assertEquals(query, inbox.take())
        inbox.detach(InviteLinkListener { hints += 100 })
        inbox.offer(fragment)
        assertEquals(2, hints)
        inbox.detach(listener)
        inbox.offer(query)
        assertEquals(2, hints)
        assertEquals(query, inbox.take())
    }

    @Test fun manifestDeclaresOneVerifiedExportedInviteLinkTarget() {
        val document = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val ns = "http://schemas.android.com/apk/res/android"
        val activities = document.getElementsByTagName("activity")
        val targets = (0 until activities.length).map { activities.item(it) as Element }
            .filter { it.getAttributeNS(ns, "name").endsWith(".InviteLinkActivity") }
        assertEquals(1, targets.size)
        val activity = targets.single()
        assertEquals("true", activity.getAttributeNS(ns, "exported"))
        assertEquals("true", activity.getAttributeNS(ns, "noHistory"))
        val filters = activity.getElementsByTagName("intent-filter")
        assertEquals(1, filters.length)
        val filter = filters.item(0) as Element
        assertEquals("true", filter.getAttributeNS(ns, "autoVerify"))
        fun names(tag: String): Set<String> {
            val nodes = filter.getElementsByTagName(tag)
            return (0 until nodes.length).map { (nodes.item(it) as Element).getAttributeNS(ns, "name") }.toSet()
        }
        assertEquals(setOf("android.intent.action.VIEW"), names("action"))
        assertEquals(setOf("android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"), names("category"))
        val data = filter.getElementsByTagName("data")
        assertEquals(2, data.length)
        val paths = (0 until data.length).map { data.item(it) as Element }.map { entry ->
            assertEquals(3, entry.attributes.length)
            assertEquals("https", entry.getAttributeNS(ns, "scheme"))
            assertEquals("aamirazeez.com", entry.getAttributeNS(ns, "host"))
            assertFalse(entry.hasAttributeNS(ns, "pathPrefix") || entry.hasAttributeNS(ns, "pathPattern"))
            entry.getAttributeNS(ns, "path")
        }
        assertEquals(listOf("/after-you/link", "/after-you/link/"), paths.sorted())
        // No other plugin component claims web links or verification.
        val allFilters = document.getElementsByTagName("intent-filter")
        assertEquals(1, (0 until allFilters.length).count { (allFilters.item(it) as Element).hasAttributeNS(ns, "autoVerify") })
        assertEquals(2, document.getElementsByTagName("data").length)
    }

    @Test fun trampolinesUseTheirOwnTaskAndStayOutOfRecents() {
        val document = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val ns = "http://schemas.android.com/apk/res/android"
        val activities = document.getElementsByTagName("activity")
        val byName = (0 until activities.length).map { activities.item(it) as Element }
            .associateBy { it.getAttributeNS(ns, "name").substringAfterLast('.') }
        listOf("InviteLinkActivity", "NotificationOpenActivity").forEach { name ->
            val activity = byName.getValue(name)
            assertTrue(name, activity.hasAttributeNS(ns, "taskAffinity"))
            assertEquals(name, "", activity.getAttributeNS(ns, "taskAffinity"))
            assertEquals(name, "true", activity.getAttributeNS(ns, "excludeFromRecents"))
        }
    }

    @Test fun everyLaunchBringsTheGameForwardButOnlyFreshViewsCarryALink() {
        data class Case(val action: String?, val data: String?, val history: Boolean, val restored: Boolean, val expected: String)
        listOf(
            Case(InviteLinkPolicy.VIEW, fragment, false, false, fragment),
            Case(InviteLinkPolicy.VIEW, "https://evil.test/#friend-$id", false, false, InviteLinkPolicy.INVALID),
            Case(InviteLinkPolicy.VIEW, fragment, true, false, ""),
            Case(InviteLinkPolicy.VIEW, fragment, false, true, ""),
            Case("android.intent.action.MAIN", fragment, false, false, ""),
        ).forEach { case ->
            val inbox = InviteLinkInbox()
            var launches = 0
            InviteLinkPolicy.deliver(case.action, case.data, case.history, case.restored, inbox) { launches += 1 }
            assertEquals(case.toString(), 1, launches)
            assertEquals(case.toString(), case.expected, inbox.take())
        }
    }
}
