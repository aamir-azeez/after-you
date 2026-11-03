package com.aamirazeez.afteryou.nativebridge

/** Editable native presentation copy; identifiers and platform behavior stay separate. */
internal object PlayerCopy {
    // afteryouandroid.7cb1b6d6341e
    const val AFTERYOUANDROID_7CB1B6D6341E = "The store request could not complete. Please try again."
    // afteryouandroid.aa6ed713d8f8
    const val AFTERYOUANDROID_AA6ED713D8F8 = "Reopen the app before trying again."
    // afteryouandroid.3c0277c73111
    const val AFTERYOUANDROID_3C0277C73111 = "This build does not have purchases configured."
    // afteryouandroid.78cd9eaa1477
    const val AFTERYOUANDROID_78CD9EAA1477 = "The store request could not start."
    // afteryouandroid.0ca1ab0e2240
    const val AFTERYOUANDROID_0CA1AB0E2240 = "The purchase settings for this store are invalid."
    // devicelock.title: the screen lock prompt before the recovery code shows or is copied.
    const val DEVICE_LOCK_TITLE = "Show your recovery details"
    // devicelock.description
    const val DEVICE_LOCK_DESCRIPTION = "Use your screen lock to see or copy your recovery code."
    // afteryouandroid.214e3ef36387
    const val AFTERYOUANDROID_214E3EF36387 = "Restart the app before changing purchase identity or store."
    // afteryouandroid.a32dd7a64c03
    const val AFTERYOUANDROID_A32DD7A64C03 = "Complete the existing store dialog."
    // afteryouandroid.00c3e92b5eb3
    const val AFTERYOUANDROID_00C3E92B5EB3 = "Refresh the store before purchasing."
    // afteryouandroid.56bb71497d29
    const val AFTERYOUANDROID_56BB71497D29 = "The purchase was not able to begin."
    // notificationdelivery.04c4f3638050
    const val NOTIFICATIONDELIVERY_04C4F3638050 = "When your friend leaves a turn for you."
    // notificationdelivery.a5b249a65e48
    const val NOTIFICATIONDELIVERY_A5B249A65E48 = "A common moment has been updated."
    // notificationdelivery.d4901221095c
    const val NOTIFICATIONDELIVERY_D4901221095C = "Open After You to see your shared moment."
    // notificationdelivery.redo_requested
    const val NOTIFICATIONDELIVERY_REDO_REQUESTED = "Your friend asked for a redo"
    // notificationdelivery.pollen_title (also the lock screen text)
    const val NOTIFICATIONDELIVERY_POLLEN_TITLE = "Your monthly Pollen is here"
    // notificationdelivery.pollen_body: %s is the amount, grouped by pollenAmount
    const val NOTIFICATIONDELIVERY_POLLEN_BODY = "+%s Pollen from Full Journey"
    // notificationdelivery.pollen_channel
    const val NOTIFICATIONDELIVERY_POLLEN_CHANNEL = "Monthly Pollen"
    // notificationdelivery.pollen_channel_description
    const val NOTIFICATIONDELIVERY_POLLEN_CHANNEL_DESCRIPTION = "When your monthly Full Journey Pollen arrives."

    fun pollenBody(amount: Long): String = NOTIFICATIONDELIVERY_POLLEN_BODY.replace("%s", pollenAmount(amount))

    /** Thousands always grouped with a comma, whatever the phone's locale (4500 -> "4,500"). */
    fun pollenAmount(amount: Long): String {
        val digits = amount.coerceAtLeast(0).toString()
        val grouped = StringBuilder(digits.length + digits.length / 3)
        digits.forEachIndexed { index, digit ->
            if (index > 0 && (digits.length - index) % 3 == 0) grouped.append(',')
            grouped.append(digit)
        }
        return grouped.toString()
    }
}
