# Native turn notifications

The native bridge receives Firebase Cloud Messaging data messages, displays generic friend-turn notifications in the background, and signals an authoritative refresh in the foreground. Notifications require explicit opt-in and Android permission. It does not poll with WorkManager or modify gameplay, credentials or photo data.

## Configuration and dependency

Exact `com.google.firebase:firebase-messaging:25.1.3` in native Gradle and both Godot export declarations. No Firebase Analytics SDK, Firebase KTX modules or google-services Gradle plugin. The checked-in lockfile pins the resolved dependencies for both native variants. Firebase Android public resource configuration must exist in the final merged APK: `google_app_id`, `google_api_key`, `gcm_defaultSenderId`, `project_id`. Native validates a complete matching Android app/sender descriptor; missing configuration yields `supported=false` and `configured=false`. Normal FirebaseInitProvider initialization makes cold service delivery independent of Godot startup. Auto-init defaults false in manifest and is enabled only by the explicit opted-in token request. Keep the Android configuration input outside source control. Server service-account and signing secrets must never be placed in APK resources.

## Methods and signals

All methods are on existing AfterYouAndroid JNI singleton. Use dynamic callv, not Object.has_method. Responses are `notification_result(request_id, operation, json)` or `notification_error(request_id, operation, code)`. Errors contain bounded categories, no underlying provider exception/token/body. Each native request terminates once. A native local request deadline is 9 seconds, permission 90 seconds; wrappers should use 10/100 seconds. Permission/token operations require explicit user opt-in. Token/route content stays private and is never logged.

| Method | Operation | Result |
|---|---|---|
| `notification_status(id)` | `status` | `{supported,configured,opted_in,permission_granted,channel_enabled,registration_pending,generation}` |
| `notification_request_permission(id)` | `request_permission` | Same status; actual system grant is checked, denial leaves opt-in false. Permission alone does not fetch a token. |
| `notification_get_token(id)` | `get_token` | `{token,generation}` only when configured, opted-in and permission granted. |
| `notification_set_binding(epoch,token,generation,id)` | `set_binding` | `{bound:true,binding_epoch,generation}` after caller verifies matching authenticated server acknowledgement. |
| `notification_clear_binding(id)` | `clear_binding` | `{cleared:true,generation}`; clears local routes/notifications and invalidates pending acknowledgements, retains opt-in preference. |
| `notification_pending_route(id)` | `pending_route` | `{route:{}}` or `{route:exact_event_fields}` for a current bound notification the user tapped. |
| `notification_ack_route(event_id,id)` | `ack_route` | `{acknowledged:true,event_id}`; duplicate acknowledgement is idempotent, missing/invalid route is an error. |
| `notification_disable(id)` | `disable` | `{disabled:true,token_deleted,generation}`; local opt-out/route clear happens first. `token_deleted=false` is truthful provider cleanup failure and remains retryable; this never claims server unregister. |

Status, clear_binding and pending_route are local-only and safe without configured Firebase or opt-in. Disable clears locally even if provider cleanup errors/times out; callers inspect status and retry remote/token cleanup rather than falsely declaring it complete. At most one token-fetch/delete provider task is active; another receives `notification_provider_busy`. SDK callbacks that arrive after a request timeout cannot complete a reused request ID. A provider task may outlast the local deadline; retry after it settles or on a later app session, without restoring an old account binding.

`notification_received(event_json)` is emitted only while the Godot main loop is ready and the Activity resumed. It requests a normal authoritative refresh and never changes gameplay. `notification_token_changed(json)` carries only `{generation,registration_pending}`, also foreground-only. Cold token changes are retained as a hash/pending-registration state and synchronized on next foreground; there is no background device-registration capability by this bridge.

## Exact backend payload / account lifecycle

FCM sends DATA ONLY; every data value is a string and the exact key set is:

`schema_version="1",event_id,kind="turn_ready",room_id,room_family="legacy"|"relay",revision,binding_epoch`

`relay` means any v2 chapter, including First Steps. Only turn_ready is accepted; reaction pushes are rejected. Room IDs are exactly 22 base64url characters. Revision is a positive canonical integer, at most 2^53 - 1, representing the actual accepted room revision. Native copy is generic “Your friend left a turn”; it does not claim that the recipient currently owns the next role. No photo, name, recording, credentials, invitation, URL or arbitrary notification text is accepted.

Client persists a 22-character base64url epoch per identity/device credential lifecycle BEFORE registering. POST `/v1/notifications/registration` is `{schema_version:1,token,binding_epoch}` using existing game authentication; response `{registered:true,binding_epoch}`. Only then bind native with exact token and the generation from get_token. DELETE uses `{schema_version:1,binding_epoch}` and response `{unregistered:true}`. These authenticated HTTP operations belong to the game API; the native bridge does not send them.

Generation changes when opt-in/account binding is invalidated, not on the FCM onNewToken callback. Matching onNewToken and getToken callbacks therefore do not falsely fail first registration. Changed token hashes still reject stale acknowledgements. Explicit identity recovery/replacement/deletion must immediately call clear_binding before awaiting remote operations; old epoch messages, taps and queued foreground callbacks are then rejected. `notification_binding` is a valid name for existing Keystore-backed Godot storage; no native vault algorithm changes are required.

## Delivery and tap behavior

The service works without a Godot Activity. A no-backup SQLite ledger stores only typed event metadata/token hashes, with bounded event/room counts, stale-revision suppression and 7-day retention. Post retries reuse a stable room notification tag with onlyAlertOnce. This does not claim distributed exactly-once delivery. Foreground delivery leaves an event pending until the guarded main-thread signal is emitted, then marks it handled; a background transition falls back to a visible notification. Default importance channel “Friend turns”, private visibility and generic public lockscreen text are used.

The immutable explicit tap PendingIntent targets a nonexported small native Activity that marks the event tapped durably and brings the launcher forward. It does not use CLEAR_TOP to destroy a running game Activity. Godot polls the pending route after authentication and verifies membership/server state at a safe point before opening; no autojoin, recording interruption or arbitrary URL is performed. Validate warm tap behavior against the exported game Activity, including an active unsaved turn.

## Validation

Run the JVM policy/request tests and isolated Android tests from `native`:

```powershell
.\gradlew.bat :plugin:testDebugUnitTest
.\gradlew.bat :plugin:connectedDebugAndroidTest "-Pandroid.testInstrumentationRunnerArguments.class=com.aamirazeez.afteryou.nativebridge.NotificationStoreDeviceTest,com.aamirazeez.afteryou.nativebridge.NotificationBridgeDeviceTest"
```

The Android tests use isolated SQLite files and a fake SDK/permission boundary. They cover binding generation, delivery deduplication, durable tapped routes, foreground consumption and stale callbacks. They do not establish actual system permission or Firebase delivery.

Validate the configured application on a Google Play services device or Google APIs emulator: permission grant/deny, authenticated registration and binding, a partner commit while the recipient is backgrounded, one generic OS notification, cold and warm taps with authoritative room reads, account invalidation and foreground refresh. Android force-stop suppresses delivery until the application is reopened. Normal process absence is a separate case. Physical-device/OEM/Doze behavior must be measured independently; no fixed delivery-time guarantee is provided.

Run `scripts/test-android-firebase.ps1`, `python scripts/test-native-notices.py`, and `python scripts/check-apk-notices.py <exported.apk>` to verify build configuration and notice packaging.

Build option: pass an explicit absolute private path as `scripts/build-android.ps1 -FirebaseConfigPath <private-google-services.json>`. This forwards `-PafterYouFirebaseConfig=<absolute-path>` to native Gradle/packagePlugin for both AAR variants. The build checks all four exact values in both AARs and the final APK without printing them, or requires absence when unconfigured. The default is unconfigured; no environment or source-tree config fallback is used. The optional task validates the exact app package and generates the four public values under build/generated/res; an unconfigured run removes only its own previous generated XML. The input JSON and generated XML are not source files.

## SDK compatibility

FCM 25.1.0 introduced Firebase Installation ID registration and deprecated `getToken`, `deleteToken` and `onNewToken`; 25.1.3 still implements these token APIs when `firebase_messaging_installation_id_enabled` is absent/false. This patch deliberately retains that mode because the authenticated server contract targets FCM registration tokens. The replacement `register`/`unregister` plus `onRegistered`/`onUnregistered` requires enabling the FID flag and coordinating the sender/identifier lifecycle; it is a future migration, not a drop-in rename. Compiler deprecation warnings are retained. The current manifest does not enable FID mode.

References: [official Android SDK release notes](https://firebase.google.com/support/release-notes/android), [FCM Android registration modes](https://firebase.google.com/docs/cloud-messaging/android/get-started), [FirebaseMessaging API](https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessaging). The pinned SDK enforces the mode through the manifest flag.

The offline Native runtime components and Native artifact notices entries cover the native lockfile, Firebase transitives, and the upstream BSD-3-Clause protobuf-lite license. `check-apk-notices.py` rejects missing native runtime inventory entries before verifying exact packaged notice bytes. Run this check on the exact APK intended for distribution.
