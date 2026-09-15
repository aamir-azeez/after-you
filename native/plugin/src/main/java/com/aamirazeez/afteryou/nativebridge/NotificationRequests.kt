package com.aamirazeez.afteryou.nativebridge

/** Main-thread request tickets prevent an expired SDK callback from completing a reused ID. */
internal class NotificationRequests {
    data class Ticket(val id: String, val operation: String, val serial: Long)
    private var serial = 0L
    private val active = mutableMapOf<String, Ticket>()

    fun begin(id: String, operation: String): Ticket? {
        if (id.length !in 1..128 || active.containsKey(id) || active.size >= 32) return null
        return Ticket(id, operation, ++serial).also { active[id] = it }
    }
    fun current(ticket: Ticket): Boolean = active[ticket.id] == ticket
    fun finish(ticket: Ticket): Boolean {
        if (!current(ticket)) return false
        active.remove(ticket.id)
        return true
    }
    fun all(): List<Ticket> = active.values.toList()
}
