extends RefCounted
## Durable file writes for room attempts. On Android the plugin writes a sibling
## temporary file, syncs it to storage and renames it over the target, so a true
## result survives a power cut. Elsewhere (desktop builds and tests) Godot writes,
## flushes and renames: nothing in GDScript syncs a file descriptor, so that path is
## not power-cut safe, and such builds never tell the server they keep attempts.

const NativeBridge = preload("res://services/native_bridge.gd")
const SERVICE := "history_files"

## Whether this build has the synced native write.
static func durable_available() -> bool:
	var native := NativeBridge.singleton(SERVICE)
	return native != null and native.has_method("history_write")

static func write(path: String, bytes: PackedByteArray) -> bool:
	if not path.begins_with("user://"): return false
	var native := NativeBridge.singleton(SERVICE)
	if native != null and native.has_method("history_write"):
		return bool(native.callv("history_write", [ProjectSettings.globalize_path(path), bytes]))
	var directory := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	var temporary := path + ".new"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	if failed:
		DirAccess.remove_absolute(temporary)
		return false
	# Windows will not rename over an existing file.
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK
