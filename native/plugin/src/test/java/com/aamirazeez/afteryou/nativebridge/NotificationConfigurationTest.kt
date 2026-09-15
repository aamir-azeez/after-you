package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class NotificationConfigurationTest {
    @Test fun onlyCompleteMatchingPublicAndroidConfigurationEnablesFeature() {
        val app = "1:123456789012:android:0123456789abcdef"
        val key = "AIza" + "x".repeat(35)
        assertTrue(NotificationConfiguration.valid(app, key, "123456789012", "synthetic-after-you"))
        assertFalse(NotificationConfiguration.valid(app, key, "987654321098", "synthetic-after-you"))
        assertFalse(NotificationConfiguration.valid(app, key, "123456789012", null))
        assertFalse(NotificationConfiguration.valid(null, key, "123456789012", "synthetic-after-you"))
        assertFalse(NotificationConfiguration.valid(app, "private-key-material", "123456789012", "synthetic-after-you"))
    }
    @Test fun missingOrNonAndroidConfigurationStaysUnavailable() {
        assertFalse(NotificationConfiguration.valid(null, null, null, null))
        assertFalse(NotificationConfiguration.valid("1:123456789012:web:0123456789abcdef", "AIza" + "x".repeat(35), "123456789012", "synthetic-after-you"))
    }
}
