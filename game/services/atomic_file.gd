extends RefCounted
## The one way to replace a small file whole. A new copy is written beside the
## file, flushed, read back and only then renamed over the old one, so a write
## cut off part way leaves the previous file readable.
##
## With keep_backup the previous file first moves to `path.backup`, and comes
## back if the rename fails. Each store keeps its own file suffixes, so files
## already on players' phones stay readable.
##
## Not power-cut safe on its own: nothing in GDScript syncs a file descriptor
## (native_files.gd has the synced Android write for room attempts).

const TMP := ".tmp"
const BACKUP := ".backup"

static func write_text(path: String, text: String, keep_backup: bool = false, tmp_suffix: String = TMP) -> bool:
	return write_bytes(path, text.to_utf8_buffer(), keep_backup, tmp_suffix)

static func write_bytes(path: String, bytes: PackedByteArray, keep_backup: bool = false, tmp_suffix: String = TMP) -> bool:
	var temporary := path + tmp_suffix
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var stored := file.get_error() == OK
	file.close()
	if not stored or FileAccess.get_file_as_bytes(temporary) != bytes:
		_remove(temporary)
		return false
	var backup := path + BACKUP
	if keep_backup and FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and _remove(backup) != OK:
			_remove(temporary)
			return false
		if _rename(path, backup) != OK:
			_remove(temporary)
			return false
	if _rename(temporary, path) == OK: return true
	# Windows may refuse to rename over an existing file: remove it and try once more.
	if not keep_backup and FileAccess.file_exists(path) and _remove(path) == OK and _rename(temporary, path) == OK: return true
	if keep_backup and not FileAccess.file_exists(path) and FileAccess.file_exists(backup): _rename(backup, path)
	# The old file is still whole; a leftover copy would only confuse a later read.
	# With no file left at `path`, the new copy is the newest whole one, so it stays for read_text.
	if FileAccess.file_exists(path): _remove(temporary)
	return false

## The text of `path`, or of the copy a write cut off between its steps left
## behind (the new copy, then the backup). `accept` checks a candidate's text;
## the first one it accepts is returned. "" when none is readable and accepted.
static func read_text(path: String, accept: Callable = Callable(), tmp_suffix: String = TMP) -> String:
	for candidate: String in [path, path + tmp_suffix, path + BACKUP]:
		if not FileAccess.file_exists(candidate): continue
		var bytes := FileAccess.get_file_as_bytes(candidate)
		if bytes.is_empty() and FileAccess.get_open_error() != OK: continue
		var text := bytes.get_string_from_utf8()
		if accept.is_valid() and not accept.call(text): continue
		return text
	return ""

## Removes the file and every copy a write may have left beside it.
static func remove(path: String, tmp_suffix: String = TMP) -> bool:
	var removed := true
	for candidate: String in [path, path + tmp_suffix, path + BACKUP]:
		if FileAccess.file_exists(candidate) and _remove(candidate) != OK: removed = false
	return removed

static func _rename(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))

static func _remove(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
