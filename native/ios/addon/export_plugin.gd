@tool
extends EditorPlugin
## iOS export settings for the After You native services. CI copies this addon, the built
## extension and any configured SDKs into its own game copy; nothing here is in game/.
## Each SDK is added only when its configuration is present, so an unconfigured build has
## no purchase or push SDK at all and behaves as before.

var ios_export: EditorExportPlugin

func _enter_tree() -> void:
	ios_export = AfterYouIOSExport.new()
	add_export_plugin(ios_export)

func _exit_tree() -> void:
	remove_export_plugin(ios_export)
	ios_export = null

class AfterYouIOSExport extends EditorExportPlugin:
	const ROOT := "res://addons/after_you_ios/"
	## FirebaseMessaging and the core frameworks it needs. No Analytics, no advertising ID.
	const FIREBASE := ["FirebaseMessaging", "GoogleDataTransport", "FirebaseCore", "FirebaseCoreInternal", "FirebaseInstallations", "GoogleUtilities", "FBLPromises", "nanopb"]

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_os_name() == "iOS"

	func _get_name() -> String:
		return "AfterYouIOS"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		# Keychain, notification center and the local notification ledger.
		add_apple_embedded_platform_linker_flags("-framework Security -framework UserNotifications -lsqlite3")
		if store_configured() and DirAccess.dir_exists_absolute(ROOT + "sdk/RevenueCat.xcframework"):
			add_apple_embedded_platform_embedded_framework(ROOT + "sdk/RevenueCat.xcframework")
		if push_configured():
			for name: String in FIREBASE:
				add_apple_embedded_platform_embedded_framework(ROOT + "sdk/firebase/%s.xcframework" % name)
			add_apple_embedded_platform_bundle_file(ROOT + "config/GoogleService-Info.plist")
			# Firebase's static frameworks rely on Objective-C categories and libc++.
			add_apple_embedded_platform_linker_flags("-ObjC -lc++")
			# The plugin hands the APNs token to Firebase itself and turns auto-init on only
			# after the player opts in. Background hints wake the app to post a notification.
			add_apple_embedded_platform_plist_content("<key>FirebaseAppDelegateProxyEnabled</key>\n<false/>\n<key>FirebaseMessagingAutoInitEnabled</key>\n<false/>\n<key>UIBackgroundModes</key>\n<array>\n<string>remote-notification</string>\n</array>\n")

	static func store_configured() -> bool:
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://app_config.json"))
		if not config is Dictionary: return false
		return str(config.get("purchase_mode", "")) in ["app_store", "test_store"] and not str(config.get("revenuecat_public_key", "")).is_empty()

	static func push_configured() -> bool:
		if not FileAccess.file_exists(ROOT + "config/GoogleService-Info.plist"): return false
		for name: String in FIREBASE:
			if not DirAccess.dir_exists_absolute(ROOT + "sdk/firebase/%s.xcframework" % name): return false
		return true
