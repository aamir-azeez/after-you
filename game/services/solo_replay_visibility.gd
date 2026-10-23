extends RefCounted
## Hides exact verified replay parts from this device's library without
## touching the gameplay journal that contains them.
const Canonical = preload("res://core/v2/canonical.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const VERSION := 1
const DEFAULT_PATH := "user://solo-replay-visibility.json"
const MAX_BYTES := 262144

var path := DEFAULT_PATH
var _hidden: Dictionary = {}
## The content of every removed part: the same part listed from another copy
## of its attempt (an archive kept by a retry or Redo) has another key.
var _hidden_content: Dictionary = {}
## Whether the removals were read from the file itself, not a copy a cut-off
## write left beside it; only then may a write move it to the backup.
var _from_primary := false
var last_error := ""

func _init(storage_path: String = DEFAULT_PATH) -> void:
	path = storage_path
	_load()

func is_hidden(row: Dictionary) -> bool:
	var key := _key(row)
	if key.is_empty(): return false
	return str(_hidden.get(key, "")) == str(row.get("content_id", "")) or _hidden_content.has(str(row.get("content_id", "")))

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
	_hidden_content[content_id] = true
	_from_primary = true
	return true

func _key(row: Dictionary) -> String:
	var key: Variant = row.get("visibility_key")
	var content: Variant = row.get("content_id")
	if not key is String or key.is_empty() or key.length() > 512 or not content is String: return ""
	if content.length() != 64 or not content.is_valid_hex_number(false): return ""
	return key

func _load() -> void:
	_hidden.clear()
	_hidden_content.clear()
	_from_primary = false
	last_error = ""
	if not AtomicFile.read_candidates(path).any(func(candidate: String) -> bool: return FileAccess.file_exists(candidate)): return
	# The file, else the copy a write cut off between its steps left beside it.
	var text := AtomicFile.read_text(path, func(candidate: String) -> bool: return _parse(candidate) is Dictionary)
	var parsed: Variant = _parse(text)
	if not parsed is Dictionary:
		last_error = "Some replay removals could not be loaded."
		return
	_from_primary = FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text
	for key: Variant in parsed.hidden:
		var digest: Variant = parsed.hidden[key]
		if key is String and not key.is_empty() and key.length() <= 512 and digest is String and digest.length() == 64 and digest.is_valid_hex_number(false):
			_hidden[key] = digest
			_hidden_content[digest] = true

## The removals file's contents, or null when `text` is not one.
static func _parse(text: String) -> Variant:
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_BYTES: return null
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), VERSION) or not parsed.get("hidden") is Dictionary: return null
	return parsed

func _save(next: Dictionary) -> bool:
	var bytes := JSON.stringify({"schema_version":VERSION,"hidden":next})
	if bytes.to_utf8_buffer().size() > MAX_BYTES:
		last_error = "Replay removals are full."
		return false
	# A file that could not be read is never moved over the backup.
	if AtomicFile.replace(path, bytes.to_utf8_buffer(), AtomicFile.Backup.MOVE if _from_primary else AtomicFile.Backup.NONE) != AtomicFile.Step.DONE:
		last_error = "Replay could not be removed."
		return false
	return true
