package com.aamirazeez.afteryou.nativebridge

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * Android backup for the player's own Google account: journals, keepsakes,
 * settings and kept room history, chosen by the game's plan within the quota.
 * Nothing goes to the cloud unless the backup is end-to-end encrypted (Android 9+
 * with a screen lock); a phone-to-phone transfer is always allowed. Credentials,
 * kept photos and alert state live in noBackupFilesDir, which Android never backs up.
 */
class AfterYouBackupAgent : BackupAgent() {
    override fun onFullBackup(data: FullBackupDataOutput) {
        // Android's own constants; BackupPolicy mirrors them (1 and 2) for its JVM tests.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || data.transportFlags and (FLAG_CLIENT_SIDE_ENCRYPTION_ENABLED or FLAG_DEVICE_TO_DEVICE_TRANSFER) == 0) return
        val root = filesDir
        val planFile = File(root, BackupPolicy.PLAN)
        val plan = if (planFile.isFile && planFile.length() <= BackupPolicy.MAX_PLAN_BYTES) planFile.readText() else null
        for (file in BackupPolicy.select(root, plan, data.quota)) fullBackupFile(file, data)
    }

    // Full backup only (android:fullBackupOnly="true"); there is no key-value data.
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput?, newState: ParcelFileDescriptor?) = Unit
    override fun onRestore(data: BackupDataInput?, appVersionCode: Int, newState: ParcelFileDescriptor?) = Unit
}
