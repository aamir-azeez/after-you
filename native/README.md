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

`copy_recovery(player_id, recovery_code)` uses the same request signals with operation `copy_recovery`. It accepts only the server's 22-character identity and 43-character recovery code, both base64url, and copies a three-line recovery note on the Activity UI thread. The device token is never included. Android's sensitive-content flag is set before the clipboard write to suppress the system preview where supported. This flag does not encrypt the clipboard or prevent pasting into another app. The success payload is only `{"copied":true}`; invalid values and failed writes report bounded errors without echoing secrets. Invalid input preserves existing clipboard content. An older plugin without this method returns `native_operation_unavailable` through the GDScript wrapper.

Names permit lowercase letters, digits, `_`, `-` and `.`, starting with a letter, up to 64 characters. Values are bounded to 16 KiB. AES-256-GCM encrypts each value with a fresh nonce and authenticates the credential name. The key is non-exportable in Android Keystore; ciphertext uses atomic writes in `noBackupFilesDir`, outside Android cloud backup. Uninstalling or losing the device key requires the player's recovery code. Errors never fall back to plaintext. Desktop tests intentionally report Keystore unavailable.

## Verification

```powershell
.\gradlew.bat :plugin:testDebugUnitTest
.\gradlew.bat :plugin:connectedDebugAndroidTest
```

The first command checks store-mode/key validation, storage bounds and recovery-note formatting/validation. The second needs an authorized Android device/emulator and checks Keystore round trips, ciphertext at rest, deletion, credential-name tampering and sensitive clipboard metadata. Clipboard tests use only synthetic data with an injected writer; they never read or change the real device clipboard. Run Godot wrapper checks from the repository root with `godot --headless --path game --script ../native/tests/test_wrappers.gd`.

Real purchase verification is separate: on Android, configure the actual Test Store, inspect offerings, complete a purchase, verify `full_journey`, cancel a purchase, refresh after entitlement removal, restore, and verify the RevenueCat dashboard events. A build, unit test or mocked UI does not establish these outcomes.

References: [Godot v2 plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html), [RevenueCat Android](https://www.revenuecat.com/docs/getting-started/installation/android), [RevenueCat Test Store](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store), [Android sensitive clipboard content](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste#sensitive-content).
