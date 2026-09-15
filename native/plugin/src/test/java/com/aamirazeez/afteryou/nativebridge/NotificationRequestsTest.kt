package com.aamirazeez.afteryou.nativebridge

import org.junit.Assert.*
import org.junit.Test

class NotificationRequestsTest {
    @Test fun expiredCallbackCannotCompleteAReusedRequestId() {
        val book = NotificationRequests()
        val expired = book.begin("request", "get_token")!!
        assertTrue(book.finish(expired)) // Same terminal transition used by the timeout.
        val newer = book.begin("request", "disable")!!
        assertFalse(book.current(expired))
        assertFalse(book.finish(expired))
        assertTrue(book.current(newer))
        assertTrue(book.finish(newer))
    }
    @Test fun duplicatesAndUnboundedOutstandingWorkAreRejected() {
        val book = NotificationRequests()
        assertNull(book.begin("", "status"))
        assertNull(book.begin("x".repeat(129), "status"))
        for (n in 0 until 32) assertNotNull(book.begin("request$n", "status"))
        assertNull(book.begin("request0", "get_token"))
        assertNull(book.begin("overflow", "status"))
        assertEquals(32, book.all().size)
    }
    @Test fun closeUsesTheSameExactlyOnceTerminalTransition() {
        val book = NotificationRequests()
        val tickets = (0..3).map { book.begin("r$it", "status")!! }
        book.all().forEach { assertTrue(book.finish(it)) }
        tickets.forEach { assertFalse(book.finish(it)) }
        assertTrue(book.all().isEmpty())
    }
}
