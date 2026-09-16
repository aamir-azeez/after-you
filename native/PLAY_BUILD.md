# Google Play bundle

The Google Play build uses `Release`, a private build configuration, and an explicitly selected existing signing certificate. The default build remains the signed, debuggable RevenueCat Test Store APK. Neither path overwrites an existing candidate or the separately promoted download.

Install the pinned Godot 4.7.2 editor/templates, Java 17, Android SDK 36, build tools 36.1.0 and NDK 29.0.14206865. The native plugin uses compile/target SDK 36; the exported application targets API 36. RevenueCat 10.15.1 resolves Google Play Billing 8.3.0 through the locked dependency graph.

Download [bundletool 1.18.3](https://github.com/google/bundletool/releases/tag/1.18.3). The build requires `bundletool-all-1.18.3.jar` with SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`. Python 3 is used only for the native ELF verification script.

Create an app configuration outside the checkout with exactly these fields:

```json
{
  "api_base_url": "https://your-service.example",
  "revenuecat_public_key": "goog_YOUR_PUBLIC_SDK_KEY",
  "purchase_mode": "google_play",
  "entitlement_id": "full_journey_play"
}
```

Use the Google Play public SDK key, never a RevenueCat secret key. Bind only the Play one-time product to `full_journey_play`; the existing Test Store entitlement is `full_journey`. The native customer response includes the entitlement's SDK store. Play admission requires the configured entitlement and `PLAY_STORE`, including legitimate Google license-test purchases. A demo or promotional entitlement cannot unlock the Play application.

```powershell
./scripts/build-android.ps1 -Configuration Release -ExportFormat AAB `
  -PrivateRoot D:/AfterYou-builds `
  -AppConfigPath D:/AfterYou-builds/config/play.json `
  -FirebaseConfigPath D:/AfterYou-builds/config/google-services.json `
  -SigningKeyPath D:/AfterYou-builds/signing/upload.keystore `
  -SigningPasswordPath D:/AfterYou-builds/signing/upload.password.dpapi `
  -SigningAlias existing-upload-alias `
  -ExpectedSignerSha256 YOUR_EXISTING_CERTIFICATE_SHA256 `
  -BundletoolJar D:/AfterYou-builds/toolchain/bundletool-all-1.18.3.jar `
  -PythonExe python `
  -OutputPath 'D:/AfterYou-builds/deliverables/candidates/play/After You.aab'
```

The password file is a Windows DPAPI `ConvertFrom-SecureString` value readable by the current Windows profile. The build never creates or substitutes a Release signing key. Back up the existing keystore and its password independently; the DPAPI file alone is not a portable password backup. Passwords pass through process environment variables, never command-line arguments or plaintext files.

The explicit configuration and AAB export settings are applied during the build, then the exact original source bytes are restored in `finally`. Use an isolated checkout and one build at a time. Process termination can bypass cleanup; discard or inspect an interrupted build checkout before reusing it. Firebase configuration remains optional and its four generated resources are verified against the explicit file.

The output is validated with bundletool and JAR signature verification. The adjacent `.verification` directory contains bundle configuration and a universal inspection APK explicitly signed with the selected upload certificate. APK checks cover identity, target SDK, non-debuggable Release, HTTPS-only network policy, billing permission and Firebase resources. Packaged app configuration must exactly match the selected input. Every native ELF is checked for 16 KB load-segment alignment and for RELRO page rounding that would protect other writable data; padding gaps remain allowed. `zipalign -c -P 16 4` verifies APK alignment. No emulator result or Play-delivered signature is implied by these structural checks.

Google Play App Signing may use a different certificate from the upload certificate. If it does, an already installed sideloaded APK cannot be updated in place by the Play app. Before uninstalling, preserve account recovery details and explicitly transfer photos where needed; local solo progress does not have an account-transfer guarantee. Validate the Play-installed build separately using a tester account.

Run the build helpers independently:

```powershell
./scripts/test-android-artifacts.ps1
./scripts/test-android-play.ps1
python ./scripts/test-android-pages.py
```

References: [target API requirements](https://developer.android.com/google/play/requirements/target-sdk), [16 KB page support](https://developer.android.com/guide/practices/page-sizes), [Billing support deadlines](https://developer.android.com/google/play/billing/deprecation-faq), [bundletool](https://developer.android.com/tools/bundletool), [Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756).
