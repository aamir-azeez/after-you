class_name LicenseCatalog
extends RefCounted
## Attribution comes from bundled notices and the running engine, without network requests.

const FILES := {
	"After You": "res://assets/licenses/after-you-MIT.txt",
	"Fredoka font": "res://assets/fonts/fredoka-OFL.txt",
	"Nunito font": "res://assets/fonts/nunito-OFL.txt",
	"RevenueCat Android 10.15.1": "res://assets/licenses/RevenueCat-10.15.1-MIT.txt",
	"Native runtime components": "res://assets/licenses/native-components.txt",
	"Native artifact notices": "res://assets/licenses/native-notices.txt",
	"Apache License 2.0": "res://assets/licenses/Apache-2.0.txt",
	"Android SDK license": "res://assets/licenses/Android-SDK-License.txt",
}
const LLVM_FILES := {
	"LLVM libc++": "res://assets/licenses/LLVM-libcxx.txt",
	"LLVM libc++abi": "res://assets/licenses/LLVM-libcxxabi.txt",
	"LLVM libunwind": "res://assets/licenses/LLVM-libunwind.txt",
	"LLVM compiler runtime": "res://assets/licenses/LLVM-compiler-rt.txt",
}
const GODOT_NOTICE := "res://assets/licenses/Godot-4.7.2-MIT.txt"

static func file_paths() -> PackedStringArray:
	var paths := PackedStringArray([GODOT_NOTICE])
	for path in FILES.values():
		paths.append(path)
	for path in LLVM_FILES.values():
		paths.append(path)
	return paths

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append({"title":"After You", "text":_read(FILES["After You"])})
	result.append({"title":"Godot Engine", "text":Engine.get_license_text()})
	result.append({"title":"Godot third-party components", "text":_engine_dependencies()})
	for title in FILES:
		if title != "After You":
			result.append({"title":title, "text":_read(FILES[title])})
	var runtime_parts := PackedStringArray()
	for title in LLVM_FILES:
		runtime_parts.append(str(title) + "\n\n" + _read(LLVM_FILES[title]))
	result.append({"title":"LLVM Android runtime", "text":"The Android C++ runtime retains the following LLVM runtime notices.\n\n" + "\n\n--------------------\n\n".join(runtime_parts)})
	return result

static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "This license notice is unavailable in this build."
	return FileAccess.get_file_as_string(path)

static func _engine_dependencies() -> String:
	var parts := PackedStringArray()
	for component in Engine.get_copyright_info():
		parts.append(str(component.get("name", "Engine component")))
		for part in component.get("parts", []):
			for copyright_line in part.get("copyright", []):
				parts.append(str(copyright_line))
			parts.append("License: " + str(part.get("license", "")))
			for file in part.get("files", []):
				parts.append("  " + str(file))
		parts.append("")
	var texts: Dictionary = Engine.get_license_info()
	var names: Array = texts.keys()
	names.sort()
	for name in names:
		parts.append(str(name) + "\n\n" + str(texts[name]) + "\n")
	return "\n".join(parts)
