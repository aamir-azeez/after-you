extends RefCounted
## Hides exact verified replay parts from this device's library without
## touching the gameplay journal that contains them.
const Canonical = preload("res://core/v2/canonical.gd")
const VERSION := 1
const DEFAULT_PATH := "user://solo-replay-visibility.json"
const MAX_BYTES := 262144

var path := DEFAULT_PATH
var _hidden: Dictionary = {}
var last_error := ""

func _init(storage_path: String = DEFAULT_PATH) -> void:
	path = storage_path
	_load()

func is_hidden(row: Dictionary) -> bool:
	var key := _key(row)
	if key.is_empty(): return false
	return str(_hidden.get(key, "")) == str(row.get("content_id", ""))

func hide(row: Dictionary) -> bool:
	last_error = ""
	var key := _key(row)
	var content_id := str(row.get("content_id", ""))
	if key.is_empty() or content_id.length() != 64 or not content_id.is_valid_hex_number(false):
		last_error = "That replay could not be removed."
		return false
	var next := _hidden.duplicate(true)
	next[key] = content_id
	if not _save(next): return false
	_hidden = next
	return true

func _key(row: Dictionary) -> String:
	var key: Variant = row.get("visibility_key")
	var content: Variant = row.get("content_id")
	if not key is String or key.is_empty() or key.length() > 512 or not content is String: return ""
	if content.length() != 64 or not content.is_valid_hex_number(false): return ""
	return key

func _load() -> void:
	_hidden.clear()
	last_error = ""
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Some replay removals could not be loaded."
		return
	if file.get_length() < 1 or file.get_length() > MAX_BYTES:
		file.close()
		last_error = "Some replay removals could not be loaded."
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("schema_version") != VERSION or not parsed.get("hidden") is Dictionary:
		last_error = "Some replay removals could not be loaded."
		return
	for key: Variant in parsed.hidden:
		var digest: Variant = parsed.hidden[key]
		if key is String and not key.is_empty() and key.length() <= 512 and digest is String and digest.length() == 64 and digest.is_valid_hex_number(false):
			_hidden[key] = digest

func _save(next: Dictionary) -> bool:
	var bytes := JSON.stringify({"schema_version":VERSION,"hidden":next})
	if bytes.to_utf8_buffer().size() > MAX_BYTES:
		last_error = "Replay removals are full."
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Replay could not be removed."
		return false
	file.store_string(bytes)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay or JSON.parse_string(FileAccess.get_file_as_string(temporary)) == null:
		last_error = "Replay could not be removed."
		return false
	if FileAccess.file_exists(path):
		var backup := path + ".backup"
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup)) != OK:
			last_error = "Replay could not be removed."
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		var backup := path + ".backup"
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path))
		last_error = "Replay could not be removed."
		return false
	return true
