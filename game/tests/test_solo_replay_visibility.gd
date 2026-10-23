extends SceneTree
const Visibility = preload("res://services/solo_replay_visibility.gd")
var checks := 0
var failures := 0
var path := "user://solo-replay-visibility-%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var row := {"visibility_key":"relay:attempt:part-0:abc","content_id":"a".repeat(64)}
	var visibility := Visibility.new(path)
	_check(not visibility.is_hidden(row), "A replay is visible before removal")
	_check(visibility.hide(row) and visibility.is_hidden(row), "Removing a replay hides its exact verified content")
	var next := Visibility.new(path)
	_check(next.is_hidden(row), "Replay visibility persists after restart")
	var replacement := row.duplicate(true)
	replacement.content_id = "b".repeat(64)
	_check(not next.is_hidden(replacement), "A different content identity remains visible")
	_check(not next.hide({"visibility_key":"bad","content_id":"not-a-digest"}), "Invalid rows cannot be removed")
	for version: Variant in ["1", [1], {}, true]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"schema_version": version, "hidden": {}}))
		file.close()
		var odd := FileAccess.get_file_as_string(path)
		_check(not Visibility.new(path).is_hidden(row) and FileAccess.get_file_as_string(path) == odd, "A visibility file whose version is not a number hides nothing and stays unchanged")
	_recovery(row)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Solo replay visibility: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A write cut off between its two renames, or a damaged file beside a good
## backup, keeps every removal; the same part listed again from another copy of
## its attempt (an archive after a retry from a checkpoint) stays removed.
func _recovery(row: Dictionary) -> void:
	var other := {"visibility_key":"relay:attempt:part-1:def","content_id":"c".repeat(64)}
	var moved := path + "-moved"
	var store := Visibility.new(moved)
	_check(store.hide(row), "A part is removed")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(moved), ProjectSettings.globalize_path(moved + ".backup"))
	_check(Visibility.new(moved).is_hidden(row), "Cut off after the old file became the backup, the removal is still read")
	var damaged := path + "-damaged"
	store = Visibility.new(damaged)
	store.hide(row)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(damaged), ProjectSettings.globalize_path(damaged + ".backup"))
	var file := FileAccess.open(damaged, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	store = Visibility.new(damaged)
	_check(store.is_hidden(row), "A damaged file beside a good backup still hides what the backup hides")
	store.hide(other)
	var kept_backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(damaged + ".backup"))
	_check(kept_backup is Dictionary and kept_backup.get("hidden", {}).get(row.visibility_key) == row.content_id, "The good backup is never replaced by the damaged file")
	var reopened := Visibility.new(damaged)
	_check(reopened.is_hidden(row) and reopened.is_hidden(other), "A later removal keeps every earlier one")
	var archived := row.duplicate(true)
	archived.visibility_key = "archive:relay:attempt:part-0:abc"
	_check(reopened.is_hidden(archived), "The same part from another copy of its attempt stays removed")
	for target: String in [moved, damaged]:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(target + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(target + suffix))

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
