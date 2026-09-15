package com.aamirazeez.afteryou.nativebridge

import java.lang.ref.WeakReference

internal interface NotificationObserver {
    /** True means queued for foreground delivery, not that gameplay was updated. */
    fun offer(event: TurnNotification): Boolean
    fun tokenChanged()
}

/** Default app process only. No Activity, Godot instance or credential is retained statically. */
internal object NotificationRuntime {
    private var observer = WeakReference<NotificationObserver>(null)
    @Synchronized fun attach(value: NotificationObserver) { observer = WeakReference(value) }
    @Synchronized fun detach(value: NotificationObserver) {
        if (observer.get() === value) observer.clear()
    }
    @Synchronized fun foreground(event: TurnNotification): Boolean = observer.get()?.offer(event) == true
    @Synchronized fun tokenChanged() { observer.get()?.tokenChanged() }
}
