package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

/** The clear after a paste import takes only our own copy or the details just imported. */
class RecoveryClipPolicyTest {
    private val code = "r".repeat(43)

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
