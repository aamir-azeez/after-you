extends SceneTree
## A chapter journal whose every copy is unreadable (a write cut off on a
## chapter's first save leaves an empty or half file and no backup) moves aside
## and the chapter starts over with the started-fresh note, as the main save
## does (local_save.gd start_fresh_if_unreadable). Before, the chapter showed
## its error card on every open with only Back.
const Journey = preload("res://services/relay_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Preview = preload("res://relay_preview.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://unreadable-journal-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for damaged: String in ["", "{\"version\": 1, \"generation\": 1, \"relay\": {"]:
		_journal_starts_fresh(damaged)
	_readable_copy_wins()
	await _screen_opens()
	print("UNREADABLE CHAPTER JOURNAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _journal_starts_fresh(damaged: String) -> void:
	var path := directory + "/relay-%d.json" % checks
	_write(path, damaged)
	var journey := Journey.new(path, null, Registry.RELAY)
	journey.load_data()
	_check(not journey.read_only and journey.last_error == PlayerCopy.LOCAL_SAVE_STARTED_FRESH, "An unreadable journal (%d bytes) starts the chapter over with the note: %s" % [damaged.length(), journey.last_error])
	_check(journey.pairs().is_empty() and journey.prior_recording().is_empty() and journey.stage_id() == str(Registry.definition(Registry.RELAY).stages[0].id), "...at its first stage")
	_check(not FileAccess.file_exists(path) and _aside(path).size() == 1, "...and its damaged copy is kept beside it under another name")
	if not _aside(path).is_empty():
		_check(FileAccess.get_file_as_string(directory + "/" + _aside(path)[0]) == damaged, "...with the same bytes")
	var cold := Journey.new(path, null, Registry.RELAY)
	cold.load_data()
	_check(not cold.read_only and cold.last_error.is_empty(), "A later open is an ordinary fresh chapter")

func _readable_copy_wins() -> void:
	# A damaged primary beside a damaged backup and nothing else still starts
	# over; a newer version's file never does (it stays held).
	var path := directory + "/relay-both.json"
	_write(path, "{")
	_write(path + ".backup", "")
	var journey := Journey.new(path, null, Registry.RELAY)
	journey.load_data()
	_check(not journey.read_only and _aside(path).size() == 2 and not FileAccess.file_exists(path + ".backup"), "Every unreadable copy moves aside")
	# Cut off before its first rename: only a half new copy, no file yet.
	var first := directory + "/relay-first.json"
	_write(first + ".tmp", "{\"version\": 1, \"gen")
	var started := Journey.new(first, null, Registry.RELAY)
	started.load_data()
	_check(not started.read_only and started.last_error == PlayerCopy.LOCAL_SAVE_STARTED_FRESH and not FileAccess.file_exists(first + ".tmp") and _aside(first).size() == 1, "A half new copy with no file starts the chapter over: " + started.last_error)
	var newer := directory + "/relay-newer.json"
	_write(newer, JSON.stringify({"version": 99, "generation": 1}))
	var held := Journey.new(newer, null, Registry.RELAY)
	held.load_data()
	_check(held.read_only and FileAccess.file_exists(newer) and _aside(newer).is_empty(), "A save from a newer version is never moved aside")

## The real open of the chapter: its own journal path, loaded on the worker.
func _screen_opens() -> void:
	var path := str(Registry.descriptor(Registry.RELAY).local_path)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_write(path, "")
	var scene: Node = load(Registry.solo_scene(Registry.RELAY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	Preview.request_staged_build(scene.scene_file_path)
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while is_instance_valid(scene) and scene.mode not in ["ready", "error"] and Time.get_ticks_msec() < deadline: await process_frame
	_check(is_instance_valid(scene) and scene.mode == "ready", "The chapter opens on its ready card, not its error card: " + str(scene.mode))
	scene._leaving = true
	scene.queue_free()
	await process_frame
	for name: String in _aside(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir() + "/" + name))
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _aside(path: String) -> Array:
	var found: Array = []
	for name: String in DirAccess.get_files_at(path.get_base_dir()):
		if name.begins_with(path.get_file() + ".") and name.contains(".unreadable-"): found.append(name)
	return found

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
