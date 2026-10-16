extends RefCounted
## The one way to replace a small file whole. A new copy is written beside the
## file, flushed, read back and only then renamed over the old one, so a write
## cut off part way leaves the previous file readable.
##
## The previous file can be kept as `path.backup` (see Backup). Each store
## keeps its own file suffixes, so files already on players' phones stay
## readable.
##
## Not power-cut safe on its own: nothing in GDScript syncs a file descriptor
## (native_files.gd has the synced Android write for room attempts).

const TMP := ".tmp"
const BACKUP := ".backup"

## How a write keeps the previous file as `path.backup`. MOVE renames it there
## and renames it back if the new copy cannot land. COPY copies it there, so
## `path` itself stays whole until the new copy replaces it.
enum Backup { NONE, MOVE, COPY }
## Where a write stopped. DONE when the new copy is in place.
enum Step { DONE, OPEN, VERIFY, BACKUP, RENAME }

static func write_text(path: String, text: String, keep_backup: bool = false, tmp_suffix: String = TMP) -> bool:
	return write_bytes(path, text.to_utf8_buffer(), keep_backup, tmp_suffix)

static func write_bytes(path: String, bytes: PackedByteArray, keep_backup: bool = false, tmp_suffix: String = TMP) -> bool:
	return replace(path, bytes, Backup.MOVE if keep_backup else Backup.NONE, tmp_suffix) == Step.DONE

## write_bytes for a store that tells its players which step failed.
static func replace(path: String, bytes: PackedByteArray, backup: Backup = Backup.NONE, tmp_suffix: String = TMP) -> Step:
	var temporary := path + tmp_suffix
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return Step.OPEN
	file.store_buffer(bytes)
	file.flush()
	var stored := file.get_error() == OK
	file.close()
	if not stored or FileAccess.get_file_as_bytes(temporary) != bytes:
		_remove(temporary)
		return Step.VERIFY
	var previous := path + BACKUP
	if backup != Backup.NONE and FileAccess.file_exists(path) and _keep(path, previous, backup) != OK:
		_remove(temporary)
		return Step.BACKUP
	if _rename(temporary, path) == OK: return Step.DONE
	# Windows may refuse to rename over an existing file: remove it and try once more.
	if FileAccess.file_exists(path) and _remove(path) == OK and _rename(temporary, path) == OK: return Step.DONE
	if backup == Backup.MOVE and not FileAccess.file_exists(path) and FileAccess.file_exists(previous): _rename(previous, path)
	# A file is still at `path` (the previous one, or the backup put back): the write
	# failed, so its new copy goes too, or a later read could take the refused change.
	# With nothing at `path`, the new copy is the newest whole one, so it stays for reads.
	if FileAccess.file_exists(path): _remove(temporary)
	return Step.RENAME

## Every place a write may leave this file's contents, in the order to read
## them: the file, the new copy a cut-off write left, then the backup.
static func read_candidates(path: String, tmp_suffix: String = TMP) -> Array[String]:
	return [path, path + tmp_suffix, path + BACKUP]

## The text of `path`, or of the copy a write cut off between its steps left
## behind (the new copy, then the backup). `accept` checks a candidate's text;
## the first one it accepts is returned. "" when none is readable and accepted.
static func read_text(path: String, accept: Callable = Callable(), tmp_suffix: String = TMP) -> String:
	for candidate: String in read_candidates(path, tmp_suffix):
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
	for candidate: String in read_candidates(path, tmp_suffix):
		if FileAccess.file_exists(candidate) and _remove(candidate) != OK: removed = false
	return removed

## Renames `source` to `stem` + its SHA-256 + ".json", a recovery name no store
## reads, writes or removes. When that name already holds the same bytes,
## `source` is removed instead, since its bytes are kept there. False when the
## move cannot be confirmed.
static func move_aside(source: String, stem: String) -> bool:
	var digest := FileAccess.get_sha256(source)
	if digest.is_empty():
		return false
	var aside := stem + digest + ".json"
	if FileAccess.file_exists(aside):
		return FileAccess.get_sha256(aside) == digest and DirAccess.remove_absolute(source) == OK
	return DirAccess.rename_absolute(source, aside) == OK and FileAccess.get_sha256(aside) == digest

static func _keep(path: String, previous: String, backup: Backup) -> Error:
	if backup == Backup.COPY: return DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(previous))
	if FileAccess.file_exists(previous) and _remove(previous) != OK: return FAILED
	return _rename(path, previous)

static func _rename(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))

static func _remove(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
