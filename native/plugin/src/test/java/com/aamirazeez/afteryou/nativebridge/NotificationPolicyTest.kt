package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class NotificationPolicyTest {
    private fun valid() = mapOf("schema_version" to "1", "event_id" to "event_1234567890123456",
        "kind" to "turn_ready", "room_id" to "r".repeat(22), "room_family" to "relay",
        "revision" to "12", "binding_epoch" to "a".repeat(22))

    @Test fun acceptsOnlyTheExactTypedContract() {
        val parsed = NotificationPolicy.parse(valid())
        assertNotNull(parsed)
        assertEquals(valid(), parsed!!.fields())
        assertNotNull(NotificationPolicy.parse(valid() + ("room_family" to "legacy")))
        assertNull(NotificationPolicy.parse(valid() + ("kind" to "reaction")))
        assertNull(NotificationPolicy.parse(valid() + ("url" to "https://example.test")))
        assertNull(NotificationPolicy.parse(valid() - "binding_epoch"))
        assertNull(NotificationPolicy.parse(valid() + ("schema_version" to "2")))
    }

    @Test fun revisionMustBeCanonicalAndExactlyRepresentableByTheCoordinator() {
        listOf("0", "-1", "+1", "01", "1.0", "1e2", " 1", "1\n", "9007199254740992", "99999999999999999999").forEach {
            assertNull(NotificationPolicy.parse(valid() + ("revision" to it)))
        }
        assertEquals(1L, NotificationPolicy.parse(valid() + ("revision" to "1"))!!.revision)
        assertEquals(NotificationPolicy.MAX_REVISION,
            NotificationPolicy.parse(valid() + ("revision" to "9007199254740991"))!!.revision)
    }

    @Test fun roomIdentifierMustMatchTheServerExactly() {
        for (length in listOf(8, 16, 21, 23, 128)) {
            assertNull(NotificationPolicy.parse(valid() + ("room_id" to "r".repeat(length))))
        }
        assertNotNull(NotificationPolicy.parse(valid() + ("room_id" to "r".repeat(22))))
    }

    @Test fun noArbitraryRouteOrNotificationCopyIsAccepted() {
        for (field in listOf("event_id", "room_id", "binding_epoch")) {
            listOf("", "../other", "bad room", "x".repeat(129), "é".repeat(22), "https://example.test").forEach {
                assertNull(NotificationPolicy.parse(valid() + (field to it)))
            }
        }
        assertNull(NotificationPolicy.parse(valid() + ("kind" to "custom_title")))
        assertNull(NotificationPolicy.parse(valid() + ("room_family" to "https")))
    }

    @Test fun hostingHintUsesItsOwnExactSchemaAndCanonicalHostEpoch() {
        val host = "h".repeat(22)
        val hint = (valid() - "revision") + mapOf("kind" to "friend_room_available", "host_id" to host,
            "publication_epoch" to "12", "event_id" to "${host}_12")
        assertEquals(hint, NotificationPolicy.parse(hint)!!.fields())
        assertNull(NotificationPolicy.parse(hint + ("revision" to "12")))
        assertNull(NotificationPolicy.parse(hint - "host_id"))
        assertNull(NotificationPolicy.parse(hint + ("publication_epoch" to "01")))
        assertNull(NotificationPolicy.parse(hint + ("publication_epoch" to "9007199254740992")))
        assertNull(NotificationPolicy.parse(hint + ("event_id" to "${host}_13")))
        assertNull(NotificationPolicy.parse(hint + ("host_id" to "x".repeat(22))))
    }

    @Test fun redoRequestUsesTheTurnShapeWithItsOwnEventId() {
        val hint = valid() + mapOf("kind" to "redo_requested", "event_id" to "redo_" + "a1".repeat(32))
        val parsed = NotificationPolicy.parse(hint)
        assertNotNull(parsed)
        assertEquals(hint, parsed!!.fields())
        assertTrue(hint.values.sumOf { it.length } <= 1024)
        assertNull(NotificationPolicy.parse(hint + ("host_id" to "h".repeat(22))))
        assertNull(NotificationPolicy.parse((hint - "revision") + ("publication_epoch" to "12")))
        assertNull(NotificationPolicy.parse(hint + ("event_id" to "event_1234567890123456")))
        assertNull(NotificationPolicy.parse(hint + ("event_id" to "redo_" + "A1".repeat(32))))
        assertNull(NotificationPolicy.parse(hint + ("kind" to "reaction")))
    }

    private fun pollen() = mapOf("schema_version" to "1", "event_id" to "pollen_" + "0a".repeat(16),
        "kind" to "pollen_monthly", "amount" to "4500", "binding_epoch" to "a".repeat(22))

    @Test fun monthlyPollenUsesItsOwnExactFiveKeySchema() {
        val parsed = NotificationPolicy.parse(pollen())
        assertNotNull(parsed)
        assertTrue(parsed!!.isPollen)
        assertEquals(4500L, parsed.amount)
        assertEquals("", parsed.roomId)
        assertEquals("", parsed.family)
        assertEquals(pollen(), parsed.fields())
        assertEquals(1L, NotificationPolicy.parse(pollen() + ("amount" to "1"))!!.amount)
        assertEquals(9_999_999L, NotificationPolicy.parse(pollen() + ("amount" to "9999999"))!!.amount)
        assertNull(NotificationPolicy.parse(pollen() + ("schema_version" to "2")))
        assertNull(NotificationPolicy.parse(pollen() + ("binding_epoch" to "short")))
    }

    @Test fun monthlyPollenRejectsMalformedEventIdsAndAmounts() {
        listOf("", "0", "01", "00", "-1", "+1", "1.0", "1e3", "4,500", " 1", "1\n", "12345678", "99999999999").forEach {
            assertNull(it, NotificationPolicy.parse(pollen() + ("amount" to it)))
        }
        listOf("pollen_" + "0a".repeat(15), "pollen_" + "0a".repeat(17), "pollen_" + "0A".repeat(16),
            "pollen_" + "g".repeat(32), "Pollen_" + "0a".repeat(16), "event_1234567890123456", "redo_" + "a1".repeat(32),
            "pollen_" + "0a".repeat(16) + "\n").forEach {
            assertNull(it, NotificationPolicy.parse(pollen() + ("event_id" to it)))
        }
    }

    @Test fun monthlyPollenRejectsExtraMissingAndMixedKeys() {
        for (key in pollen().keys) assertNull(NotificationPolicy.parse(pollen() - key))
        for (extra in listOf("room_id", "room_family", "revision", "host_id", "title", "url")) {
            assertNull(NotificationPolicy.parse(pollen() + (extra to "r".repeat(22))))
        }
        // A Pollen kind in a room hint's shape, and a room kind in Pollen's shape.
        assertNull(NotificationPolicy.parse(valid() + ("kind" to "pollen_monthly")))
        assertNull(NotificationPolicy.parse(valid() + mapOf("kind" to "pollen_monthly", "event_id" to "pollen_" + "0a".repeat(16))))
        for (kind in listOf("turn_ready", "redo_requested", "friend_room_available", "reaction")) {
            assertNull(NotificationPolicy.parse(pollen() + ("kind" to kind)))
        }
    }

    @Test fun pollenAmountIsAlwaysGroupedWithCommas() {
        val cases = mapOf(1L to "1", 999L to "999", 1000L to "1,000", 4500L to "4,500", 99_999L to "99,999",
            576_000L to "576,000", 1_234_567L to "1,234,567", 9_999_999L to "9,999,999")
        for ((amount, text) in cases) assertEquals(text, PlayerCopy.pollenAmount(amount))
        val previous = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.GERMANY)
            assertEquals("+4,500 Pollen from Full Journey", PlayerCopy.pollenBody(4500))
            assertEquals("+576,000 Pollen from Full Journey", PlayerCopy.pollenBody(576_000))
        } finally { java.util.Locale.setDefault(previous) }
        assertEquals("Your monthly Pollen is here", PlayerCopy.NOTIFICATIONDELIVERY_POLLEN_TITLE)
    }

    @Test fun monthlyPollenHasOneFixedTagAndItsOwnChannel() {
        val first = NotificationPolicy.parse(pollen())!!
        val later = NotificationPolicy.parse(pollen() + mapOf("event_id" to "pollen_" + "b1".repeat(16), "amount" to "9000"))!!
        val expected = "after_you_update:" + NotificationStore.hash("pollen_monthly")
        assertEquals(expected, NotificationDelivery.tag(first))
        assertEquals(expected, NotificationDelivery.tag(later))
        assertEquals(NotificationDelivery.POLLEN_CHANNEL, NotificationDelivery.channelFor("pollen_monthly"))
        assertEquals(NotificationDelivery.TURN_CHANNEL, NotificationDelivery.channelFor("turn_ready"))
        assertEquals(NotificationDelivery.HOSTING_CHANNEL, NotificationDelivery.channelFor("friend_room_available"))
        val turn = NotificationPolicy.parse(valid())!!
        assertEquals("after_you_update:" + NotificationStore.hash("relay:" + "r".repeat(22) + ":turn_ready"), NotificationDelivery.tag(turn))
    }

    @Test fun tokenAndScopeInputsAreBoundedWithoutTreatingTokensAsUrls() {
        assertTrue(NotificationPolicy.validToken("token_" + "a".repeat(30) + ":suffix"))
        assertFalse(NotificationPolicy.validToken("a".repeat(4097)))
        assertFalse(NotificationPolicy.validToken("a".repeat(30) + "\n"))
        assertFalse(NotificationPolicy.validToken("a".repeat(30) + " "))
        assertFalse(NotificationPolicy.validEpoch("short"))
    }
}
