package com.aamirazeez.afteryou.nativebridge

import android.app.Activity
import android.app.KeyguardManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.view.WindowManager
import androidx.annotation.RequiresApi
import org.json.JSONObject

/**
 * The phone's own screen lock in front of the recovery code. A phone with no screen lock
 * has nothing to ask, so it answers confirmed at once (with "locked": false). Android 11+
 * shows the system prompt (fingerprint, face or the screen lock); older versions open the
 * screen lock confirmation. One check at a time; every method runs on the UI thread.
 */
internal class DeviceLock(private val done: (requestId: String, payload: JSONObject?, error: String?) -> Unit) {
    private var active: String? = null
    private var cancel: CancellationSignal? = null

    fun confirm(activity: Activity, requestId: String) {
        if (active != null) { done(requestId, null, "device_check_busy"); return }
        val keyguard = activity.getSystemService(KeyguardManager::class.java)
        if (keyguard == null) { done(requestId, null, "device_check_unavailable"); return }
        if (!keyguard.isDeviceSecure) { done(requestId, JSONObject().put("confirmed", true).put("locked", false), null); return }
        active = requestId
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && prompt(activity)) return
        // Before Android 11, or when the system prompt cannot start.
        @Suppress("DEPRECATION")
        val intent = keyguard.createConfirmDeviceCredentialIntent(PlayerCopy.DEVICE_LOCK_TITLE, PlayerCopy.DEVICE_LOCK_DESCRIPTION)
        if (intent == null) { finish(true); return } // The lock went away meanwhile: nothing to ask.
        try { activity.startActivityForResult(intent, REQUEST_CODE) } catch (_: Exception) { finish(false, "device_check_unavailable") }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun prompt(activity: Activity): Boolean = try {
        val allowed = BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        val signal = CancellationSignal()
        cancel = signal
        BiometricPrompt.Builder(activity)
            .setTitle(PlayerCopy.DEVICE_LOCK_TITLE)
            .setDescription(PlayerCopy.DEVICE_LOCK_DESCRIPTION)
            .setAllowedAuthenticators(allowed)
            .build()
            .authenticate(signal, activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) = finish(true)
                override fun onAuthenticationError(code: Int, message: CharSequence?) = finish(false)
                // A single wrong finger keeps the prompt open; only an error or success ends it.
            })
        true
    } catch (_: Exception) {
        cancel = null
        false
    }

    fun handles(requestCode: Int): Boolean = requestCode == REQUEST_CODE

    fun onActivityResult(resultCode: Int) = finish(resultCode == Activity.RESULT_OK)

    /** The Activity is going away: an open prompt ends as cancelled. */
    fun close() {
        cancel?.cancel()
        finish(false)
    }

    private fun finish(confirmed: Boolean, error: String = "device_check_cancelled") {
        val id = active ?: return
        active = null
        cancel = null
        if (confirmed) done(id, JSONObject().put("confirmed", true).put("locked", true), null)
        else done(id, null, error)
    }

    companion object {
        /** Below the photo camera's reserved range (PhotoCameraRequestCodes, 0x4100 and up). */
        const val REQUEST_CODE = 0x40A7
    }
}

/** Android's screenshot and recents block for the game's window, while recovery details show. */
internal object PrivateScreen {
    fun apply(activity: Activity, on: Boolean) {
        val window = activity.window ?: return
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
