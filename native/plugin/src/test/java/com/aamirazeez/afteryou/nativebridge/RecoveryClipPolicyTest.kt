package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class RecoveryClipPolicyTest {
    private val code = "r".repeat(43)

    @Test fun theCopiedDetailsLeaveAfterTwoMinutes() {
        val now = 1_000_000L
        val deadline = now + RecoveryClipboard.LIFETIME_MS
        assertEquals(120_000L, RecoveryClipboard.LIFETIME_MS)
        assertFalse(RecoveryClipPolicy.due(RecoveryClipPolicy.deadline(deadline, now), now))
        assertFalse(RecoveryClipPolicy.due(deadline, deadline - 1))
        assertTrue(RecoveryClipPolicy.due(deadline, deadline))
        assertTrue(RecoveryClipPolicy.due(deadline, deadline + 86_400_000L))
    }

    @Test fun noDeadlineIsNeverDue() {
        assertEquals(0L, RecoveryClipPolicy.deadline(0L, 5L))
        assertEquals(0L, RecoveryClipPolicy.deadline(-3L, 5L))
        assertFalse(RecoveryClipPolicy.due(0L, Long.MAX_VALUE))
    }

    @Test fun aClockMovedBackCannotPostponeTheExpiryBeyondOneLifetime() {
        val now = 50_000L
        assertEquals(now + RecoveryClipboard.LIFETIME_MS, RecoveryClipPolicy.deadline(now + 10 * RecoveryClipboard.LIFETIME_MS, now))
        assertEquals(now + 1, RecoveryClipPolicy.deadline(now + 1, now))
    }

    @Test fun onlyOurClipOrTheImportedCodeIsCleared() {
        assertTrue(RecoveryClipPolicy.ours(RecoveryClipboard.LABEL, null, null))
        assertTrue(RecoveryClipPolicy.ours(StringBuilder(RecoveryClipboard.LABEL), null, null))
        assertFalse(RecoveryClipPolicy.ours("Shopping list", "milk", null))
        assertFalse(RecoveryClipPolicy.ours(null, null, null))
        // A note from a password manager or notes app, pasted to import.
        assertTrue(RecoveryClipPolicy.ours("Notes", "Identity: ${"i".repeat(22)}\nRecovery code: $code", code))
        assertFalse(RecoveryClipPolicy.ours("Notes", "something else", code))
        assertFalse(RecoveryClipPolicy.ours("Notes", "x".repeat(5000) + code, code))
    }

    @Test fun anImportedCodeMustHaveTheRecoveryCodeForm() {
        assertEquals(code, RecoveryClipPolicy.importedCode(code))
        listOf("", "r".repeat(42), "r".repeat(44), "r".repeat(42) + "=", "r".repeat(42) + "\n").forEach {
            assertNull(RecoveryClipPolicy.importedCode(it))
        }
        // Without a valid code only the label counts.
        assertFalse(RecoveryClipPolicy.ours("Notes", "", RecoveryClipPolicy.importedCode("")))
    }

    @Test fun theLabelMatchesTheCopiedNote() {
        assertTrue(BridgePolicy.recoveryText("i".repeat(22), code)!!.startsWith(RecoveryClipboard.LABEL + "\n"))
    }
}
