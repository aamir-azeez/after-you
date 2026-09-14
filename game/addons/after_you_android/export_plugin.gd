@tool
extends EditorPlugin

var android_export: EditorExportPlugin

func _enter_tree() -> void:
	android_export = AfterYouExport.new()
	add_export_plugin(android_export)

func _exit_tree() -> void:
	remove_export_plugin(android_export)
	android_export = null

class AfterYouExport extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return "AfterYouAndroid"

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray(["after_you_android/after-you-%s.aar" % variant])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.revenuecat.purchases:purchases:10.15.1", "org.jetbrains.kotlin:kotlin-stdlib:2.1.20"])
