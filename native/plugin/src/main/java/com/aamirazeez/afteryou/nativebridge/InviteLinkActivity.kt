package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Exported, display-less App Link target for invite links. Like NotificationOpenActivity it
 * stores the validated link in memory and brings the game forward with the launcher intent,
 * so a link never starts a second game Activity in another app's task. Godot takes the link.
 * An empty taskAffinity keeps a cold start from rooting the game's task in this Activity.
 */
class InviteLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val launch = intent
            val fromHistory = ((launch?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
            InviteLinkPolicy.deliver(launch?.action, launch?.dataString, fromHistory, savedInstanceState != null, InviteLinkRuntime.inbox) {
                packageManager.getLaunchIntentForPackage(packageName)?.let {
                    // Reuse a running game Activity without CLEAR_TOP; Godot decides when to show the link.
                    it.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    startActivity(it)
                }
            }
        } catch (_: Exception) {
            // A malformed or unexpected intent never authorizes anything.
        } finally { finish() }
    }
}
