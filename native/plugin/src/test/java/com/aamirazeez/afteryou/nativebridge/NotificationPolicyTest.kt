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

    @Test fun tokenAndScopeInputsAreBoundedWithoutTreatingTokensAsUrls() {
        assertTrue(NotificationPolicy.validToken("token_" + "a".repeat(30) + ":suffix"))
        assertFalse(NotificationPolicy.validToken("a".repeat(4097)))
        assertFalse(NotificationPolicy.validToken("a".repeat(30) + "\n"))
        assertFalse(NotificationPolicy.validToken("a".repeat(30) + " "))
        assertFalse(NotificationPolicy.validEpoch("short"))
    }
}
