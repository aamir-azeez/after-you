package com.aamirazeez.afteryou.nativebridge

import android.content.ClipData
import android.content.ClipDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Tests use synthetic values and a fake writer; they never read or replace the device clipboard. */
@RunWith(AndroidJUnit4::class)
class RecoveryClipboardDeviceTest {
    private val identity = "i".repeat(22)
    private val recovery = "r".repeat(43)

    @Test fun sensitivePlainTextIsFlaggedBeforeItsOnlyWrite() {
        var writes = 0
        val copied = RecoveryClipboard.copy(identity, recovery) { clip ->
            writes++
            assertEquals(1, clip.itemCount)
            assertEquals("After You recovery details", clip.description.label)
            assertTrue(clip.description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN))
            assertTrue(clip.description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true)
            assertTrue("The recovery note must contain exactly the two approved fields",
                clip.getItemAt(0).text.toString() == "After You recovery details\nIdentity: $identity\nRecovery code: $recovery")
            assertNull(clip.getItemAt(0).intent)
            assertNull(clip.getItemAt(0).uri)
        }
        assertTrue(copied)
        assertEquals(1, writes)
    }

    @Test fun invalidRecoveryDetailsLeaveExistingClipboardUntouched() {
        val existing = ClipData.newPlainText("existing", "synthetic previous clipboard")
        var current = existing
        assertFalse(RecoveryClipboard.copy(identity.dropLast(1), recovery) { current = it })
        assertSame(existing, current)
        assertFalse(RecoveryClipboard.copy(identity, recovery + "\n") { current = it })
        assertSame(existing, current)
    }

    @Test fun failedClipboardWriteCannotReportCopied() {
        var returnedSuccess = false
        try {
            returnedSuccess = RecoveryClipboard.copy(identity, recovery) { throw SecurityException("synthetic failure") }
            fail("A failed write must propagate to the native bounded error handler")
        } catch (_: SecurityException) {
            assertFalse(returnedSuccess)
        }
    }
}
