package com.aamirazeez.afteryou.nativebridge

import android.content.pm.ApplicationInfo
import android.content.ClipboardManager
import android.content.Intent
import android.app.Activity
import android.view.View
import com.revenuecat.purchases.CacheFetchPolicy
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogHandler
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class AfterYouAndroid(godot: Godot) : GodotPlugin(godot) {
    private val storageExecutor = Executors.newSingleThreadExecutor()
    private val photoExecutor = Executors.newSingleThreadExecutor()
    private var optionalPhoto: OptionalPhotoCapture? = null
    private val photoClearing = AtomicBoolean(false)
    private val photoCache by lazy { PhotoCache(requireNotNull(activity).applicationContext) }
    private val pending = ConcurrentHashMap.newKeySet<String>()
    private var configured = false
    private var configuredKey = ""
    private var configuredPlayer = ""
    private var configuredMode = ""
    private var purchaseInProgress = false
    private val packages = mutableMapOf<String, Package>()
    private val secureStore by lazy { SecureStore(requireNotNull(activity).applicationContext) }

    override fun getPluginName() = "AfterYouAndroid"

    override fun onMainCreate(activity: Activity?): View? {
        optionalPhoto?.close()
        optionalPhoto = null
        // Process death has no reliable onDestroy callback. Clean abandoned output on restart,
        // even when the player never chooses another photo. This opens no camera or network.
        if (activity != null) PhotoCaptureFiles.cleanupInterrupted(activity)
        return super.onMainCreate(activity)
    }

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("request_result", String::class.java, String::class.java, String::class.java),
        SignalInfo("request_error", String::class.java, String::class.java, String::class.java, String::class.java, Boolean::class.javaObjectType),
        SignalInfo("customer_info_updated", String::class.java),
        SignalInfo("secure_result", String::class.java, String::class.java, String::class.java),
        SignalInfo("secure_error", String::class.java, String::class.java, String::class.java),
        SignalInfo("photo_result", String::class.java, String::class.java, String::class.java),
        SignalInfo("photo_error", String::class.java, String::class.java, String::class.java)
    )

    private fun begin(requestId: String): Boolean = requestId.length in 1..128 && pending.add(requestId)

    private fun success(id: String, operation: String, payload: JSONObject) {
        if (pending.remove(id)) emitSignal("request_result", id, operation, payload.toString())
    }

    private fun failure(id: String, operation: String, code: String, message: String, cancelled: Boolean = false) {
        if (pending.remove(id)) emitSignal("request_error", id, operation, code, message, cancelled)
    }

    private fun sdkFailure(id: String, operation: String, error: PurchasesError, cancelled: Boolean = false) {
        // The SDK's underlying message may contain URLs or account identifiers. Forward only its category.
        failure(id, operation, "revenuecat_${error.code.name}", if (cancelled) "Purchase cancelled." else "The store request could not complete. Please try again.", cancelled)
    }

    private fun onUi(id: String, operation: String, needsConfiguration: Boolean = true, work: () -> Unit) {
        if (!begin(id)) return
        val currentActivity = activity
        if (currentActivity == null) {
            failure(id, operation, "activity_unavailable", "Reopen the app before trying again.")
            return
        }
        currentActivity.runOnUiThread {
            if (needsConfiguration && !configured) {
                failure(id, operation, "not_configured", "Purchases are not configured for this build.")
                return@runOnUiThread
            }
            try { work() } catch (_: Exception) {
                failure(id, operation, "native_request_failed", "The store request could not start.")
            }
        }
    }

    @UsedByGodot
    fun configure(publicKey: String, playerId: String, mode: String, requestId: String) = onUi(requestId, "configure", false) {
        val invalid = BridgePolicy.configError(publicKey, playerId, mode)
        if (invalid != null) {
            failure(requestId, "configure", invalid, "The purchase configuration is invalid for this store.")
            return@onUi
        }
        val debuggable = (requireNotNull(activity).applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val buildError = BridgePolicy.buildError(mode, debuggable)
        if (buildError != null) {
            failure(requestId, "configure", buildError, "Install the Test Store build to try test purchases.")
            return@onUi
        }
        if (configured) {
            if (configuredKey != publicKey || configuredPlayer != playerId || configuredMode != mode) {
                failure(requestId, "configure", "configuration_locked", "Restart the app before changing purchase identity or store.")
            } else refreshCustomer(requestId, "configure")
            return@onUi
        }
        // The SDK infers Test Store from its test_ public key. An explicit mode/key check prevents
        // accidentally using a Play key in a test build or a Test Store key in a production build.
        Purchases.logHandler = SilentPurchaseLogs
        Purchases.logLevel = LogLevel.ERROR
        Purchases.configure(PurchasesConfiguration.Builder(requireNotNull(activity).applicationContext, publicKey)
            .appUserID(playerId)
            .diagnosticsEnabled(false)
            .automaticDeviceIdentifierCollectionEnabled(false)
            .build())
        configured = true
        configuredKey = publicKey
        configuredPlayer = playerId
        configuredMode = mode
        Purchases.sharedInstance.updatedCustomerInfoListener = com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener { info ->
            emitSignal("customer_info_updated", customerJson(info).toString())
        }
        refreshCustomer(requestId, "configure")
    }

    @UsedByGodot
    fun get_offerings(requestId: String) = onUi(requestId, "get_offerings") {
        Purchases.sharedInstance.getOfferingsWith(
            onError = { sdkFailure(requestId, "get_offerings", it) },
            onSuccess = { offerings ->
                packages.clear()
                success(requestId, "get_offerings", offeringsJson(offerings))
            })
    }

    @UsedByGodot
    fun get_customer_info(requestId: String) = onUi(requestId, "get_customer_info") {
        refreshCustomer(requestId, "get_customer_info")
    }

    private fun refreshCustomer(requestId: String, operation: String) {
        Purchases.sharedInstance.getCustomerInfoWith(
            fetchPolicy = CacheFetchPolicy.FETCH_CURRENT,
            onError = { sdkFailure(requestId, operation, it) },
            onSuccess = { success(requestId, operation, customerJson(it)) })
    }

    @UsedByGodot
    fun purchase_package(offeringId: String, packageId: String, requestId: String) = onUi(requestId, "purchase_package") {
        if (purchaseInProgress) {
            failure(requestId, "purchase_package", "purchase_in_progress", "Finish the current store dialog first.")
            return@onUi
        }
        val selected = packages["$offeringId\u0000$packageId"]
        if (selected == null) {
            failure(requestId, "purchase_package", "package_not_loaded", "Refresh the store before purchasing.")
            return@onUi
        }
        purchaseInProgress = true
        try {
            Purchases.sharedInstance.purchaseWith(
                PurchaseParams.Builder(requireNotNull(activity), selected).build(),
                onError = { error, cancelled ->
                    purchaseInProgress = false
                    sdkFailure(requestId, "purchase_package", error, cancelled)
                },
                onSuccess = { _, info ->
                    purchaseInProgress = false
                    success(requestId, "purchase_package", customerJson(info))
                })
        } catch (_: Exception) {
            purchaseInProgress = false
            failure(requestId, "purchase_package", "purchase_failed", "The purchase could not start.")
        }
    }

    @UsedByGodot
    fun restore_purchases(requestId: String) = onUi(requestId, "restore_purchases") {
        if (purchaseInProgress) {
            failure(requestId, "restore_purchases", "purchase_in_progress", "Finish the current store dialog first.")
            return@onUi
        }
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { sdkFailure(requestId, "restore_purchases", it) },
            onSuccess = { success(requestId, "restore_purchases", customerJson(it)) })
    }

    private fun offeringsJson(offerings: Offerings): JSONObject {
        val items = JSONArray()
        offerings.all.values.forEach { offering ->
            val choices = JSONArray()
            offering.availablePackages.forEach { item ->
                packages["${offering.identifier}\u0000${item.identifier}"] = item
                choices.put(JSONObject().put("id", item.identifier).put("product_id", item.product.id)
                    .put("type", item.packageType.name).put("title", item.product.title)
                    .put("description", item.product.description).put("price", item.product.price.formatted)
                    .put("currency", item.product.price.currencyCode).put("price_micros", item.product.price.amountMicros))
            }
            items.put(JSONObject().put("id", offering.identifier).put("packages", choices))
        }
        return JSONObject().put("schema_version", 1).put("mode", configuredMode)
            .put("current_id", offerings.current?.identifier ?: JSONObject.NULL).put("offerings", items)
    }

    private fun customerJson(info: CustomerInfo): JSONObject {
        val entitlements = JSONObject()
        info.entitlements.all.forEach { (id, item) ->
            entitlements.put(id, JSONObject().put("active", item.isActive).put("product_id", item.productIdentifier)
                .put("sandbox", item.isSandbox).put("expires_at_ms", item.expirationDate?.time ?: JSONObject.NULL)
                .put("verification", item.verification.name))
        }
        return JSONObject().put("schema_version", 1).put("mode", configuredMode)
            .put("request_date_ms", info.requestDate.time).put("entitlements", entitlements)
    }

    private fun storage(id: String, operation: String, name: String, action: () -> JSONObject) {
        if (!begin(id)) return
        if (!BridgePolicy.validStorageName(name)) {
            pending.remove(id)
            emitSignal("secure_error", id, operation, "invalid_name")
            return
        }
        storageExecutor.execute {
            try {
                val payload = action()
                if (pending.remove(id)) emitSignal("secure_result", id, operation, payload.toString())
            } catch (_: Exception) {
                if (pending.remove(id)) emitSignal("secure_error", id, operation, "secure_storage_unavailable")
            }
        }
    }

    @UsedByGodot
    fun secure_put(name: String, value: String, requestId: String) = storage(requestId, "put", name) {
        secureStore.put(name, value)
        JSONObject().put("stored", true)
    }

    @UsedByGodot
    fun secure_get(name: String, requestId: String) = storage(requestId, "get", name) {
        val value = secureStore.get(name)
        JSONObject().put("found", value != null).put("value", value ?: JSONObject.NULL)
    }

    @UsedByGodot
    fun secure_remove(name: String, requestId: String) = storage(requestId, "remove", name) {
        secureStore.remove(name)
        JSONObject().put("removed", true)
    }

    @UsedByGodot
    fun secure_copy_recovery(playerId: String, recoveryCode: String, requestId: String) {
        val operation = "copy_recovery"
        if (!begin(requestId)) return
        fun reject(code: String) {
            if (pending.remove(requestId)) emitSignal("secure_error", requestId, operation, code)
        }
        if (BridgePolicy.recoveryText(playerId, recoveryCode) == null) {
            reject("invalid_recovery_details")
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            reject("activity_unavailable")
            return
        }
        try {
            currentActivity.runOnUiThread {
                try {
                    val clipboard = currentActivity.getSystemService(ClipboardManager::class.java)
                    if (clipboard == null) {
                        reject("clipboard_unavailable")
                        return@runOnUiThread
                    }
                    val copied = RecoveryClipboard.copy(playerId, recoveryCode) { clipboard.setPrimaryClip(it) }
                    if (!copied) {
                        reject("invalid_recovery_details")
                    } else if (pending.remove(requestId)) {
                        emitSignal("secure_result", requestId, operation, JSONObject().put("copied", true).toString())
                    }
                } catch (_: Exception) {
                    reject("clipboard_unavailable")
                }
            }
        } catch (_: Exception) {
            reject("activity_unavailable")
        }
    }

    private fun photoSuccess(id: String, operation: String, data: JSONObject) {
        if (pending.remove(id)) emitSignal("photo_result", id, operation, data.toString())
    }

    private fun photoFailure(id: String, operation: String, code: String) {
        if (pending.remove(id)) emitSignal("photo_error", id, operation, code)
    }

    /** The caller must invoke this only after an explicit optional-photo choice, never on startup. */
    @UsedByGodot
    fun photo_capture(requestId: String) {
        if (!begin(requestId)) return
        if (photoClearing.get()) { photoFailure(requestId, "capture", "photo_busy"); return }
        val current = activity
        if (current == null) { photoFailure(requestId, "capture", "activity_unavailable"); return }
        current.runOnUiThread {
            try {
                if (photoClearing.get()) { photoFailure(requestId, "capture", "photo_busy"); return@runOnUiThread }
                val flow = optionalPhoto ?: OptionalPhotoCapture(current, photoExecutor, photoCache,
                    { id, payload -> photoSuccess(id, "capture", payload) },
                    { id, code -> photoFailure(id, "capture", code) }).also { optionalPhoto = it }
                flow.begin(requestId)
            } catch (_: Exception) { photoFailure(requestId, "capture", "photo_unavailable") }
        }
    }

    @UsedByGodot
    fun photo_cancel(captureRequestId: String, requestId: String) {
        if (!begin(requestId)) return
        val current = activity
        if (current == null) { photoFailure(requestId, "cancel", "activity_unavailable"); return }
        current.runOnUiThread {
            try {
                val cancelled = optionalPhoto?.cancel(captureRequestId) ?: false
                photoSuccess(requestId, "cancel", JSONObject().put("cancelled", cancelled))
            } catch (_: Exception) { photoFailure(requestId, "cancel", "photo_unavailable") }
        }
    }

    private fun photoFile(id: String, operation: String, photoId: String, action: () -> JSONObject) {
        if (!begin(id)) return
        if (photoClearing.get()) { photoFailure(id, operation, "photo_busy"); return }
        if (!PhotoPolicy.validId(photoId)) { photoFailure(id, operation, "invalid_photo_id"); return }
        try {
            photoExecutor.execute {
                try { photoSuccess(id, operation, action()) }
                catch (_: Exception) { photoFailure(id, operation, "photo_unavailable") }
            }
        } catch (_: Exception) { photoFailure(id, operation, "photo_unavailable") }
    }

    @UsedByGodot
    fun photo_read(photoId: String, requestId: String) = photoFile(requestId, "read", photoId) { photoCache.read(photoId) }

    @UsedByGodot
    fun photo_discard(photoId: String, requestId: String) = photoFile(requestId, "discard", photoId) {
        JSONObject().put("discarded", photoCache.discard(photoId))
    }

    /** Explicit confirmed account-deletion action; never called by sign-out or normal lifecycle. */
    @UsedByGodot
    fun photo_clear(requestId: String) {
        if (!begin(requestId)) return
        if (!photoClearing.compareAndSet(false, true)) { photoFailure(requestId, "clear", "photo_busy"); return }
        val current = activity
        if (current == null) {
            photoClearing.set(false)
            photoFailure(requestId, "clear", "activity_unavailable")
            return
        }
        current.runOnUiThread {
            try {
                val cache = photoCache
                PhotoCachePurge.afterCapture(current.applicationContext, cache, photoExecutor, {
                    optionalPhoto?.close()
                    optionalPhoto = null
                }) { cleared ->
                    photoClearing.set(false)
                    if (cleared) photoSuccess(requestId, "clear", JSONObject().put("cleared", true))
                    else photoFailure(requestId, "clear", "photo_cleanup_unavailable")
                }
            } catch (_: Exception) {
                photoClearing.set(false)
                photoFailure(requestId, "clear", "photo_cleanup_unavailable")
            }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        optionalPhoto?.onActivityResult(requestCode, resultCode)
        super.onMainActivityResult(requestCode, resultCode, data)
    }

    override fun onMainDestroy() {
        optionalPhoto?.close()
        optionalPhoto = null
        photoExecutor.shutdown()
        storageExecutor.shutdown()
        super.onMainDestroy()
    }

    private object SilentPurchaseLogs : LogHandler {
        override fun v(tag: String, msg: String) = Unit
        override fun d(tag: String, msg: String) = Unit
        override fun i(tag: String, msg: String) = Unit
        override fun w(tag: String, msg: String) = Unit
        override fun e(tag: String, msg: String, throwable: Throwable?) = Unit
    }
}
