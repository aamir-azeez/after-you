package com.aamirazeez.afteryou.nativebridge

import java.lang.ref.WeakReference

/** Invite link (friend App Link) validation. Links are untrusted; the URL and code are never logged. */
internal object InviteLinkPolicy {
    const val VIEW = "android.intent.action.VIEW"
    const val MAX_LENGTH = 256
    /** Handed to Godot instead of a rejected URL so it can show its generic error. */
    const val INVALID = "invalid"
    // Code in the fragment, or the ?c= fallback; optional trailing slash. The bare /after-you
    // path, other paths, ports, user info, extra parameters and other code types never match.
    private val link = Regex("(?i:https)://(?i:aamirazeez\\.com)/after-you/link/?(?:#|\\?c=)friend-[A-Za-z0-9_-]{22}")

    fun valid(data: String?): Boolean = data != null && data.length <= MAX_LENGTH && link.matches(data)

    /**
     * Value to store for one launch: the validated URL, INVALID for a rejected view link, or null
     * to ignore (not a view, relaunched from history, or an activity restored from saved state).
     */
    fun accept(action: String?, data: String?, fromHistory: Boolean, restored: Boolean): String? {
        if (action != VIEW || fromHistory || restored) return null
        return if (valid(data)) data else INVALID
    }

    /** Offers this launch's link, if any, then always brings the game forward (history relaunches too). */
    fun deliver(action: String?, data: String?, fromHistory: Boolean, restored: Boolean, inbox: InviteLinkInbox, bringForward: () -> Unit) {
        accept(action, data, fromHistory, restored)?.let(inbox::offer)
        bringForward()
    }
}

internal fun interface InviteLinkListener { fun linkAvailable() }

/** Single-slot, take-once, memory-only inbox. A newer link replaces an untaken one. */
internal class InviteLinkInbox {
    private var pending: String? = null
    private var listener = WeakReference<InviteLinkListener>(null)

    fun offer(value: String) {
        if (value != InviteLinkPolicy.INVALID && !InviteLinkPolicy.valid(value)) return
        val current = synchronized(this) {
            pending = value
            listener.get()
        }
        current?.linkAvailable()
    }

    @Synchronized fun take(): String = (pending ?: "").also { pending = null }
    @Synchronized fun hasPending(): Boolean = pending != null
    @Synchronized fun attach(value: InviteLinkListener) { listener = WeakReference(value) }
    @Synchronized fun detach(value: InviteLinkListener) { if (listener.get() === value) listener.clear() }
}

/** Default app process only. Holds no Activity or Godot instance. */
internal object InviteLinkRuntime {
    val inbox = InviteLinkInbox()
}
