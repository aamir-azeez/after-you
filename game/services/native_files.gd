extends RefCounted
## Durable file writes for room attempts. On Android the plugin writes a sibling
## temporary file, syncs it to storage and renames it over the target, so a true
## result survives a power cut. Elsewhere (desktop builds and tests) Godot writes,
## flushes and renames: nothing in GDScript syncs a file descriptor, so that path is
## not power-cut safe, and such builds never tell the server they keep attempts.

const NativeBridge = preload("res://services/native_bridge.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
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
	return AtomicFile.write_bytes(path, bytes, false, ".new")
