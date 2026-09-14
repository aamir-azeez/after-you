# Android services

This Godot Android v2 plugin connects After You to the official RevenueCat Android SDK and Android Keystore. It contains no account credentials, secret API keys or purchase simulation.

## Pinned toolchain

| Component | Version |
| --- | --- |
| Godot Android library and editor | 4.7.2 stable |
| RevenueCat Android | 10.15.1 |
| Android Gradle Plugin | 8.9.2 |
| Gradle | 8.11.1 |
| Kotlin | 2.1.20 |
| Java | 17 |
| Android compile SDK | 35 |
| Android minimum SDK | 24 |

Gradle's distribution checksum is pinned in `gradle/wrapper/gradle-wrapper.properties`. Its wrapper JAR SHA-256 is `2db75c40782f5e8ba1fc278a5574bab070adccb2d21ca5a6e5ed840888448046`.

## Build and install

Set `JAVA_HOME` to JDK 17 and `ANDROID_HOME` to an SDK containing platform 35 and build tools 35.0.0 or newer. From this directory on Windows:

```powershell
.\gradlew.bat :plugin:packagePlugin :plugin:testDebugUnitTest --no-daemon
```

On macOS/Linux use `sh ./gradlew` with the same arguments. The package task copies the plugin and both AAR variants into `game/addons/after_you_android`. Enable its `plugin.cfg` in the Godot project, install the matching Android build template, and enable **Use Gradle Build** on the Android export preset. Keep the main Activity launch mode `standard` or `singleTop` so external store verification does not cancel a purchase.

For the complete signed Test Store APK, run `scripts/build-android.ps1 -Configuration Debug` from the repository root. It produces `After You - Test Store.apk`. RevenueCat requires a debuggable application for Test Store and terminates a release application configured with a test key. The build script rejects that combination early; the bridge also returns a safe configuration error before invoking the SDK. Use `Release` only after configuring the production platform store. The script has optional toolchain paths and a private output directory parameter. It creates signing material outside the repository, encrypts signing passwords with Windows DPAPI, reapplies the required Activity/network settings, and verifies the exported APK's signature. Back up the keystore and its password securely; a DPAPI password file requires its original Windows user profile and is not a portable password backup by itself.

The downloaded Godot 4.7.2 Android template additionally requires compile SDK 36, build tools 36.1.0 and NDK 29.0.14206865. The plugin itself compiles against SDK 35. Install the template's matching dependencies rather than assuming that the standalone plugin's SDK requirements cover the complete game.

Do not commit built AARs. The export addon also declares the pinned RevenueCat Maven dependency so Gradle packages the SDK and its dependencies in the APK; a plugin AAR alone does not embed those dependencies.

## GDScript API

Add `PurchaseService` and `DeviceSecretStore` nodes to the scene tree before calling them. Each method returns a random request ID. Connect `completed` and `failed` before starting a request; success is asynchronous. Store price labels come from `get_offerings` results, never a hardcoded currency string.

```gdscript
var purchases := PurchaseService.new()
add_child(purchases)
purchases.completed.connect(_on_purchase_result)
purchases.failed.connect(_on_purchase_error)
purchases.configure_store(public_sdk_key, anonymous_player_id, "test_store")
```

The native singleton is `AfterYouAndroid`. Its purchase methods are `configure(public_key, player_id, mode, request_id)`, `get_offerings(request_id)`, `get_customer_info(request_id)`, `purchase_package(offering_id, package_id, request_id)` and `restore_purchases(request_id)`.

Native signals:

- `request_result(request_id, operation, payload_json)`
- `request_error(request_id, operation, code, safe_message, cancelled)`
- `customer_info_updated(payload_json)`

`get_offerings` returns schema version 1, the explicit mode, the current offering ID, and an array of offerings. Each package includes its identifiers, title, description and store-formatted price.

Customer results return schema version 1, mode, request time and entitlement entries with `active`, `product_id`, `sandbox`, expiration and RevenueCat's verification result. No receipt, purchase token or original customer identifier is emitted to GDScript. The client entitlement is for local presentation; premium room hosting still requires the backend entitlement check.

The wrapper never grants an entitlement on cancellation, network error or native-plugin absence. A failed network refresh leaves the last SDK result visible; the UI must not mistake it for a newly verified purchase. Restoring purchases is an explicit player action and may not automatically recover a Test Store purchase across different anonymous IDs. Use the game's recovery flow to restore the same player identity.

## Store configuration

`test_store` accepts only a `test_` RevenueCat public SDK key. `google_play` accepts only a `goog_` public key. Secret `sk_` keys and mismatched modes are rejected before configuring the SDK. A process cannot switch store or identity after configuration; save a recovered identity securely and restart the app before reconfiguring it.

Create a Test Store product, a `full_journey` entitlement, and an offering/package in RevenueCat before testing. Fetch offerings and purchase a package actually returned by the SDK. Configuration without dashboard products is not a successful purchase test. A Next Gen test build must clearly identify Test Store checkout; production Play builds use a separate public key and product configuration. Galaxy is not enabled in this plugin yet and is rejected explicitly.

## Device credentials

`DeviceSecretStore` exposes `put_secret(name, value)`, `get_secret(name)` and `remove_secret(name)`. Native methods add `secure_` to the operation and receive the request ID last. Storage has separate `secure_result(request_id, operation, payload_json)` and `secure_error(request_id, operation, safe_code)` signals; do not send their payloads to telemetry or logs.

`copy_recovery(player_id, recovery_code)` uses the same request signals with operation `copy_recovery`. It accepts only the server's 22-character identity and 43-character recovery code, both base64url, and copies a three-line recovery note on the Activity UI thread. The device token is never included. Android's sensitive-content flag is set before the clipboard write to suppress the system preview where supported. This flag does not encrypt the clipboard or prevent pasting into another app. The success payload is only `{"copied":true}`; invalid values and failed writes report bounded errors without echoing secrets. Invalid input preserves existing clipboard content.

The native plugin and GDScript wrapper must ship together. Godot's Android JNI singleton dispatches Java methods through `callv`; `Object.has_method` does not inspect that Java method map and must not gate native calls. Unanswered secure operations expire after nine seconds with `native_request_timeout`, before the application's ten-second wait. Expired requests discard late callbacks; a timeout does not prove that a storage write or clipboard copy never happened.

Names permit lowercase letters, digits, `_`, `-` and `.`, starting with a letter, up to 64 characters. Values are bounded to 16 KiB. AES-256-GCM encrypts each value with a fresh nonce and authenticates the credential name. The key is non-exportable in Android Keystore; ciphertext uses atomic writes in `noBackupFilesDir`, outside Android cloud backup. Uninstalling or losing the device key requires the player's recovery code. Errors never fall back to plaintext. Desktop tests intentionally report Keystore unavailable.

## Verification

### Optional photo bridge (integration candidate)

The separately callable photo bridge contains no room, turn, account, purchase or network controller. A saved turn remains saved whether a photo is kept, skipped, cancelled or unavailable. No camera activity starts during plugin initialization. The game must offer this only as an optional action after saving a contribution; do not place it in the turn transaction or wait for it before completing gameplay.

Call the native singleton through Godot's `callv`, after connecting:

- `photo_result(request_id, operation, payload_json)`
- `photo_error(request_id, operation, safe_code)`

Methods are `photo_capture(request_id)`, `photo_cancel(capture_request_id, request_id)`, `photo_read(photo_id, request_id)`, `photo_discard(photo_id, request_id)` and the explicit account-deletion operation `photo_clear(request_id)`. IDs for native requests must be unique, 1–128 characters, as with the other plugin methods. Capture has its own user-paced lifetime; the credential wrapper's nine-second timeout is not appropriate. Cancel completes an active capture with `status:skipped`, and separately returns whether a matching flow was cancelled.

After confirmed server account deletion, `OptionalPhotoCapture.clear_photos()` invalidates local selections/reads, cancels any active capture, and requests removal of all files from the two fixed photo-cache directories, including orphan selections absent from a journal. It accepts only `photo_result(request_id, "clear", {"cleared":true})`. Native work drains the photo worker queue, blocks new photo operations during cleanup, and checks that both roots are empty before acknowledging. Failed file removal or URI revocation returns `photo_cleanup_unavailable` and preserves retry capability; a 15-second wrapper timeout does not claim that cleanup succeeded or did not happen. The caller must retain its deletion-cleanup obligation until a fresh request receives the exact acknowledgement. Credentials, simulation saves and the camera-result counter are outside these roots. Symlinks cannot redirect deletion outside them. Ordinary sign-out, scene invalidation, capture cancellation and startup do **not** invoke this full-cache operation.

Clear stops after 1,024 visited entries or 16 directory levels and reports incomplete cleanup for retry. Android 26+ uses streaming enumeration; Android 24–25 retains the platform's bulk `File.listFiles` enumeration, so its deletion count is bounded but the enumeration allocation is not. Normal photo production is already capped at 16 accepted images. The latest cleanup pass completed **58 wrapper checks, 15 JVM tests and 11 Android tests**, including orphan/nested cache removal, a 1,025-file batch/retry, symlink containment, URI-revocation retry and an unwritable-directory retry. The actual test host also cleared during consent and live camera, then demonstrated failure/retry against a kept synthetic photo. The shared capture-close/worker-cleanup helper was exercised; the Godot JNI signal path still needs its own native game test.

Capture first shows **Open camera / Skip**, then delegates an explicit shutter press to the system camera, then displays the sanitized image with **Use photo / Retake / Skip**. Android Back/camera cancellation also skips. There is one capture flow at a time. The system camera determines available lenses; the player can select the selfie lens. There is no portable forced-front-camera guarantee. Android delegates the capture without this app requesting broad storage/gallery access or a CAMERA runtime permission. The camera application may have its own storage/cloud behavior; this bridge controls only After You's temporary output file.

Only **Use photo** creates an accepted local cache image. Result `operation:capture` has `status:kept`, an opaque `photo_id`, `mime:image/jpeg`, dimensions, byte count, SHA-256, `metadata_removed:true` and `uploaded:false`. Skipping returns only `status:skipped, uploaded:false`. Photos and paths are never returned in this initial result. The explicit read method returns this metadata plus bounded `jpeg_base64`; **never log that payload or send it to analytics or an AI service**. Future optional sharing code must separately upload the player's selected bytes after its own consent flow. The current plugin never uploads anything.

The raw file is in an app-private cache subdirectory shared only through a non-exported FileProvider and a temporary URI grant to the camera. The grant is revoked on return/cancellation; raw output is deleted after decoding. On host creation, and again before a new flow, only known UUID-named orphan captures in that exact directory are revoked and removed. This cleanup opens no camera. Decode bounds limit raw files to 32 MiB and supported image dimensions, with downsampling before pixel allocation. Fresh opaque sRGB bitmap pixels are JPEG-encoded to at most 960 px per edge and 160 KiB, applying EXIF orientation before discarding metadata. A strict JPEG framing check excludes EXIF/XMP/IPTC/comment segments and trailing bytes. Kept images use a separate private cache directory not exposed by the provider, with up to 16 images and 24-hour cleanup. They are temporary optional attachments, not durable gameplay state; callers must handle eviction and use discard after sharing or removing a selection.

Activity destruction cancels an in-flight optional capture; it never restores a photo as accepted. Process death has no guaranteed destruction callback, so restart abandons the optional flow and cleans its raw output. The caller must allow a fresh explicit Capture or Skip, independently of the already saved contribution. Camera result codes are reserved atomically in a four-byte, non-backup counter before launching the camera. New controller instances never reuse an earlier code, so an old result cannot complete a fresh request. The reserved range supports 16,128 camera launches, including retakes; corruption or exhaustion returns a bounded camera error instead of resetting or wrapping the counter. Do not clear this counter to work around an active result.

Verification completed before the lifecycle follow-up: **13 JVM tests and three Android image/cache tests passed**, with the test APK targeting Android 35 on an API 35 emulator. The separate test-only Activity also exercised the actual system camera with a synthetic virtual scene: consent Skip/Back, camera Back, preview Skip, Retake/Use, explicit Read/Discard, background/return in each phase, a late result after cancellation, and idle Activity recreation followed by a fresh capture. No real person's photo or game credential was used. The image tests confirmed orientation, metadata removal, byte/dimension caps and bounded cache handling.

The subsequent lifecycle pass also completed: **15 JVM tests and six Android tests passed** on the same API 35 / target 35 configuration. The actual camera harness was recreated during consent, live camera and sanitized preview; each abandoned flow skipped without keeping a photo, and fresh capture remained available. Killing only the background test process while its system camera was foreground, then completing the old camera result, restarted the host under a new process, removed the abandoned output and showed no automatic capture, preview or keep. A new explicit Capture / Use / Read / Discard then succeeded. Synthetic storage checks verified scoped revocation calls; the emulator's grant dump did not independently expose the temporary grant, so it is not evidence of platform grant removal.

Missing-camera behavior and a physical Samsung selfie still need separate checks. The integration candidate enables the game UI, while capture and upload additionally require the service's photo-sharing capability. Actual Godot JNI photo signals, live selected-photo sharing and partner display still need end-to-end verification before this candidate is promoted. Emulator camera-harness checks do not establish those integration or physical-device outcomes. The standalone camera harness and lifecycle fault controls exist only in the disposable Android test APK; they are not game screens.

References: [Android camera intents](https://developer.android.com/media/camera/camera-intents), [temporary URI grants with FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider), [activity result lifecycle](https://developer.android.com/training/basics/intents/result), [EXIF orientation](https://developer.android.com/reference/android/media/ExifInterface).

```powershell
.\gradlew.bat :plugin:testDebugUnitTest
.\gradlew.bat :plugin:connectedDebugAndroidTest
```

The first command checks store-mode/key validation, storage bounds and recovery-note formatting/validation. The second needs an authorized Android device/emulator and checks Keystore round trips, ciphertext at rest, deletion, credential-name tampering and sensitive clipboard metadata. Clipboard tests use only synthetic data with an injected writer; they never read or change the real device clipboard. Run Godot wrapper checks from the repository root with `godot --headless --path game --script ../native/tests/test_wrappers.gd`.

Real purchase verification is separate: on Android, configure the actual Test Store, inspect offerings, complete a purchase, verify `full_journey`, cancel a purchase, refresh after entitlement removal, restore, and verify the RevenueCat dashboard events. A build, unit test or mocked UI does not establish these outcomes.

References: [Godot v2 plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html), [RevenueCat Android](https://www.revenuecat.com/docs/getting-started/installation/android), [RevenueCat Test Store](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store), [Android sensitive clipboard content](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste#sensitive-content).
