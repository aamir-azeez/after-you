extends SceneTree
## services/atomic_file.gd: the one tmp + flush + rename write every small store
## uses, and its fallback read of a copy a cut-off write left behind.
const AtomicFile = preload("res://services/atomic_file.gd")
const DIR := "user://atomic-file-test"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _read(path: String) -> String: return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"
func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
func _clear(path: String) -> void:
	for candidate: String in [path, path + ".tmp", path + ".new", path + ".backup"]:
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_plain_write()
	_backup_write()
	_copy_backup_write()
	_failed_writes()
	_fallback_read()
	_candidates()
	_remove_all()
	print("ATOMIC FILE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _plain_write() -> void:
	var path := DIR + "/plain.json"
	_clear(path)
	_check(AtomicFile.write_text(path, "first"), "A new file is written")
	_check(_read(path) == "first" and not FileAccess.file_exists(path + ".tmp"), "The file holds exactly the text and no copy is left beside it")
	_check(AtomicFile.write_text(path, "second"), "An existing file is replaced")
	_check(_read(path) == "second" and not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".backup"), "The replacement holds the new text, with no copy or backup left")
	var bytes := PackedByteArray([0, 1, 2, 255])
	_check(AtomicFile.write_bytes(path, bytes, false, ".new") and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path + ".new"), "Bytes go through a store's own copy suffix and leave nothing beside the file")
	_clear(path)

func _backup_write() -> void:
	var path := DIR + "/backed.json"
	_clear(path)
	_check(AtomicFile.write_text(path, "one", true) and not FileAccess.file_exists(path + ".backup"), "A first write has no previous file to back up")
	_check(AtomicFile.write_text(path, "two", true), "A second write succeeds")
	_check(_read(path) == "two" and _read(path + ".backup") == "one", "The previous file becomes the backup")
	_check(AtomicFile.write_text(path, "three", true) and _read(path) == "three" and _read(path + ".backup") == "two", "Each write keeps only the latest previous file as the backup")
	_clear(path)

func _copy_backup_write() -> void:
	var path := DIR + "/copied.json"
	_clear(path)
	var copy := AtomicFile.Backup.COPY
	_check(AtomicFile.replace(path, "one".to_utf8_buffer(), copy) == AtomicFile.Step.DONE and not FileAccess.file_exists(path + ".backup"), "A first copied-backup write has no previous file to keep")
	_check(AtomicFile.replace(path, "two".to_utf8_buffer(), copy) == AtomicFile.Step.DONE and _read(path) == "two" and _read(path + ".backup") == "one", "The previous file is copied to the backup and the new one replaces it")
	_check(AtomicFile.replace(path, "three".to_utf8_buffer(), copy) == AtomicFile.Step.DONE and _read(path) == "three" and _read(path + ".backup") == "two" and not FileAccess.file_exists(path + ".tmp"), "Each copied-backup write keeps only the latest previous file, with no copy left")
	_check(AtomicFile.replace(path, "four".to_utf8_buffer()) == AtomicFile.Step.DONE and _read(path + ".backup") == "two", "A write without a backup leaves an older backup alone")
	# A backup that cannot be written: the write stops before the file is touched.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".backup"))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".backup"))
	_check(AtomicFile.replace(path, "five".to_utf8_buffer(), copy) == AtomicFile.Step.BACKUP, "A backup copy that fails is reported as the backup step")
	_check(_read(path) == "four" and not FileAccess.file_exists(path + ".tmp"), "The file is untouched and no new copy is left after a failed backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".backup"))
	_clear(path)

func _failed_writes() -> void:
	# A copy that cannot be opened: the old file stays exactly as it was.
	var path := DIR + "/blocked.json"
	_clear(path)
	_check(AtomicFile.write_text(path, "kept"), "The file starts whole")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	_check(not AtomicFile.write_text(path, "lost"), "A write that cannot open its copy reports failure")
	_check(AtomicFile.replace(path, "lost".to_utf8_buffer()) == AtomicFile.Step.OPEN, "It is reported as the open step")
	_check(_read(path) == "kept", "The old file is untouched by a failed write")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	_check(AtomicFile.write_text(path, "next", true) and _read(path) == "next" and _read(path + ".backup") == "kept", "Once the block clears, a backed-up write lands and backs up the old file")
	_clear(path)
	# A rename that cannot land (a folder holds the name): the new copy stays as the newest whole one.
	var held := DIR + "/held"
	_clear(held)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(held))
	_write_raw(held + "/inside", "x")
	_check(not AtomicFile.write_text(held, "newest"), "A rename that cannot land reports failure")
	_check(_read(held + ".tmp") == "newest", "With no file at the path, the new copy is kept for a later read")
	_check(AtomicFile.read_text(held) == "newest", "read_text finds that copy")
	_check(AtomicFile.replace(held, "newer".to_utf8_buffer()) == AtomicFile.Step.RENAME, "It is reported as the rename step")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(held + "/inside"))
	_clear(held)
	_copy_rename_failure()

func _copy_rename_failure() -> void:
	# Only Windows refuses to rename over, or remove, a file that is open.
	if OS.get_name() != "Windows": return
	var path := DIR + "/open.json"
	_clear(path)
	_check(AtomicFile.write_text(path, "old"), "The file starts whole")
	var reader := FileAccess.open(path, FileAccess.READ)
	_check(AtomicFile.replace(path, "new".to_utf8_buffer(), AtomicFile.Backup.COPY) == AtomicFile.Step.RENAME, "A copied-backup write that cannot replace an open file is reported as the rename step")
	reader.close()
	_check(_read(path) == "old" and _read(path + ".backup") == "old", "The file and its backup copy both survive")
	_check(not FileAccess.file_exists(path + ".tmp"), "The refused new copy is gone")
	_clear(path)

func _fallback_read() -> void:
	var path := DIR + "/read.json"
	var valid := func(text: String) -> bool: return JSON.parse_string(text) is Dictionary
	_clear(path)
	_check(AtomicFile.read_text(path) == "", "Nothing saved reads as empty")
	_write_raw(path, "{\"v\":1}")
	_write_raw(path + ".tmp", "{\"v\":2}")
	_write_raw(path + ".backup", "{\"v\":0}")
	_check(AtomicFile.read_text(path, valid) == "{\"v\":1}", "A whole file is read first")
	_write_raw(path, "{\"v\":")
	_check(AtomicFile.read_text(path, valid) == "{\"v\":2}", "A damaged file falls back to the copy a cut-off write left")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(AtomicFile.read_text(path, valid) == "{\"v\":2}", "A missing file falls back to that copy")
	_write_raw(path + ".tmp", "half")
	_check(AtomicFile.read_text(path, valid) == "{\"v\":0}", "A half-written copy is skipped for the backup")
	_write_raw(path + ".backup", "")
	_check(AtomicFile.read_text(path, valid) == "", "Nothing accepted reads as empty")
	_write_raw(path + ".new", "{\"v\":3}")
	_check(AtomicFile.read_text(path, valid, ".new") == "{\"v\":3}", "A store's own copy suffix is read")
	_clear(path)

func _candidates() -> void:
	_check(AtomicFile.read_candidates("user://a.json") == ["user://a.json", "user://a.json.tmp", "user://a.json.backup"], "Candidates are the file, its new copy, then its backup")
	_check(AtomicFile.read_candidates("user://a.bin", ".new") == ["user://a.bin", "user://a.bin.new", "user://a.bin.backup"], "A store's own copy suffix takes the new copy's place")

func _remove_all() -> void:
	var path := DIR + "/gone.json"
	for candidate: String in [path, path + ".tmp", path + ".backup"]: _write_raw(candidate, "x")
	_check(AtomicFile.remove(path), "Removing reports success")
	_check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".backup"), "The file and every copy beside it are gone")
	_check(AtomicFile.remove(path), "Removing nothing is still a success")
