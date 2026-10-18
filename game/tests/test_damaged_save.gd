extends SceneTree
## services/local_save.gd start_fresh_if_unreadable: a main save with no
## readable copy moves aside whole and play continues on a new save, while
## every save with a readable copy recovers exactly as before.
const Storage = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0
var directories: Array[String] = []

## A save whose listed copies cannot be opened, as when another program holds them.
class LockedSave extends "res://services/local_save.gd":
	var locked: Array[String] = []
	func _init(save_path: String) -> void:
		super(save_path)
	func _copy_bytes(file_path: String) -> Variant:
		return null if file_path in locked else super(file_path)

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _run() -> void:
	_damaged_primary_only()
	_every_copy_damaged()
	_good_backup_recovers()
	_damaged_tmp_only()
	_newer_copy_stays_read_only()
	_wrong_shape_stays_read_only()
	_locked_save_is_never_moved()
	_save_repaired_before_the_move_stays()
	_failed_fresh_write_does_not_loop()
	_failed_rename_stays_read_only()
	await _main_shows_note_once()
	for directory: String in directories: _remove_tree(directory)
	print("AFTER YOU DAMAGED SAVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _directory() -> String:
	var directory := "user://damaged-save-test-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	directories.append(directory)
	return directory

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _files(directory: String) -> Array:
	var names := Array(DirAccess.get_files_at(directory))
	names.sort()
	return names

func _aside(copy: String) -> String:
	return copy + Storage.UNREADABLE + FileAccess.get_sha256(copy) + ".json"

func _good(generation: int, sound: bool) -> String:
	var value := Storage.defaults()
	value.generation = generation
	value.settings.sound = sound
	return JSON.stringify(value)

func _damaged_primary_only() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{\"version\":1,\"gen")
	var aside := _aside(path)
	var store := Storage.new(path)
	store.load_data()
	_check(store.read_only and store.last_error == PlayerCopy.LOCAL_SAVE_34FCC2945DC1 and FileAccess.file_exists(path), "load_data alone still holds an unreadable save read-only and untouched")
	_check(store.start_fresh_if_unreadable(), "An unreadable save with no other copy starts fresh")
	_check(not store.read_only and store.loaded_from.is_empty() and store.data == Storage.defaults(), "The fresh save starts from defaults and is writable")
	_check(store.last_error == PlayerCopy.LOCAL_SAVE_STARTED_FRESH, "The note for the player is set")
	_check(_files(directory) == [aside.get_file()] and FileAccess.get_file_as_string(aside) == "{\"version\":1,\"gen", "The damaged file is kept byte for byte under its recovery name, and nothing is written yet")
	var settings: Dictionary = store.data.settings.duplicate(true)
	settings.sound = false
	_check(store.update_values({"settings": settings}) and FileAccess.file_exists(path), "A setting saves on the fresh save")
	var restarted := Storage.new(path)
	restarted.load_data()
	_check(not restarted.start_fresh_if_unreadable(), "A restart after the fix moves nothing")
	_check(restarted.loaded_from == path and restarted.last_error.is_empty() and not restarted.read_only and not restarted.data.settings.sound, "A restart loads the fresh save with no note")
	_check(_files(directory) == ["journey.json", aside.get_file()], "A restart leaves exactly one recovery file")

func _every_copy_damaged() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	var damaged := {path: "{ interrupted", path + ".tmp": "", path + ".backup": "[1, 2"}
	var expected: Array = []
	for copy: String in damaged:
		_write(copy, damaged[copy])
		expected.append(_aside(copy).get_file())
	expected.sort()
	var asides: Dictionary = {}
	for copy: String in damaged: asides[copy] = _aside(copy)
	var store := Storage.new(path)
	store.load_data()
	_check(store.start_fresh_if_unreadable(), "No readable copy among primary, .tmp and .backup starts fresh")
	_check(_files(directory) == expected, "Every damaged copy moves aside and none stays where a write would replace it")
	for copy: String in damaged:
		_check(FileAccess.file_exists(asides[copy]) and FileAccess.get_file_as_string(asides[copy]) == damaged[copy], "Damaged copy kept byte for byte: " + copy.get_file())
	_check(store.flush() and store.flush(), "Two writes on the fresh save succeed")
	for copy: String in damaged:
		_check(FileAccess.get_file_as_string(asides[copy]) == damaged[copy], "Later writes leave the kept copy alone: " + copy.get_file())

func _good_backup_recovers() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{ interrupted")
	_write(path + ".backup", _good(4, false))
	var store := Storage.new(path)
	store.load_data()
	_check(store.loaded_from == path + ".backup" and store.last_error == PlayerCopy.LOCAL_SAVE_27DCFA34F3AD and not store.read_only and not store.data.settings.sound, "A good backup recovers as before")
	_check(not store.start_fresh_if_unreadable() and store.last_error == PlayerCopy.LOCAL_SAVE_27DCFA34F3AD, "A good backup shows no note")
	_check(_files(directory) == ["journey.json", "journey.json.backup"] and FileAccess.get_file_as_string(path) == "{ interrupted", "A good backup moves nothing aside")

func _damaged_tmp_only() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, _good(2, false))
	_write(path + ".tmp", "{\"version\":1,\"gen")
	var store := Storage.new(path)
	store.load_data()
	_check(store.loaded_from == path and store.last_error.is_empty() and not store.read_only, "A whole primary beside half a .tmp loads as before")
	_check(not store.start_fresh_if_unreadable(), "Half a .tmp beside a whole primary starts nothing fresh")
	_check(_files(directory) == ["journey.json", "journey.json.tmp"] and FileAccess.get_file_as_string(path + ".tmp") == "{\"version\":1,\"gen", "Half a .tmp moves nothing aside")

func _newer_copy_stays_read_only() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	var future := JSON.stringify({"version": 99, "private_future_data": "do-not-overwrite"})
	_write(path, future)
	var store := Storage.new(path)
	store.load_data()
	_check(store.read_only and store.last_error == PlayerCopy.LOCAL_SAVE_59005ED74543 and not store.start_fresh_if_unreadable(), "A save from a newer version stays read-only")
	_write(path, "{ interrupted")
	_write(path + ".backup", future)
	store.load_data()
	_check(store.read_only and not store.start_fresh_if_unreadable(), "A newer-version backup behind a damaged primary stays read-only")
	_check(_files(directory) == ["journey.json", "journey.json.backup"] and FileAccess.get_file_as_string(path + ".backup") == future, "Newer-version copies move nothing aside")

func _wrong_shape_stays_read_only() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	for text: String in ["{\"version\":\"1\"}", "{\"settings\":{}}", "{\"version\":1.5}", "{\"version\":0}", "[1, 2]", "{\"version\":1,\"settings\":[]}", "null", "{\"version\":1,\"generation\":[1]}"]:
		_write(path, text)
		var store := Storage.new(path)
		store.load_data()
		_check(store.read_only and store.last_error == PlayerCopy.LOCAL_SAVE_34FCC2945DC1 and not store.start_fresh_if_unreadable(), "A save that parses but has another shape stays read-only: " + text)
		_check(_files(directory) == ["journey.json"] and FileAccess.get_file_as_string(path) == text, "A save that parses is never moved: " + text)
	_write(path, "{ interrupted")
	_write(path + ".backup", "{\"version\":\"1\"}")
	var mixed := Storage.new(path)
	mixed.load_data()
	_check(mixed.read_only and not mixed.start_fresh_if_unreadable() and _files(directory) == ["journey.json", "journey.json.backup"], "A damaged primary beside a backup that parses moves nothing")

func _locked_save_is_never_moved() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	var whole := _good(7, false)
	_write(path, whole)
	var store := LockedSave.new(path)
	store.locked = [path]
	store.load_data()
	_check(store.read_only and store.last_error == PlayerCopy.LOCAL_SAVE_34FCC2945DC1, "A save that cannot be opened keeps the read-only hold")
	store.locked = []
	_check(not store.start_fresh_if_unreadable() and store.read_only, "A save released before the fresh start is not moved")
	_check(_files(directory) == ["journey.json"] and FileAccess.get_file_as_string(path) == whole, "The released save is kept untouched")
	var restarted := Storage.new(path)
	restarted.load_data()
	_check(restarted.loaded_from == path and restarted.data.generation == 7 and not restarted.data.settings.sound, "The next launch loads the released save")
	_write(path, "{ interrupted")
	_write(path + ".backup", "[1, 2")
	store.locked = [path + ".backup"]
	store.load_data()
	_check(store.read_only and not store.start_fresh_if_unreadable() and _files(directory) == ["journey.json", "journey.json.backup"], "A damaged primary beside a copy that cannot be opened moves nothing")

func _save_repaired_before_the_move_stays() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{ interrupted")
	var store := Storage.new(path)
	store.load_data()
	var whole := _good(5, false)
	_write(path, whole)
	_check(not store.start_fresh_if_unreadable(), "A save that parses again by the fresh start is not moved")
	_check(_files(directory) == ["journey.json"] and FileAccess.get_file_as_string(path) == whole, "The save that parses again is kept untouched")

func _failed_fresh_write_does_not_loop() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{ interrupted")
	var aside := _aside(path)
	var store := Storage.new(path)
	store.load_data()
	_check(store.start_fresh_if_unreadable(), "The damaged save moves aside")
	# A directory where the new copy is written makes every write fail.
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	_check(not store.update_values({"completed": {"first-light": true}}), "The fresh save's write fails")
	for attempt: int in 2:
		var restarted := Storage.new(path)
		restarted.load_data()
		_check(not restarted.read_only and not restarted.start_fresh_if_unreadable() and restarted.last_error.is_empty(), "A failed fresh write leaves a writable start with no note")
	_check(_files(directory) == [aside.get_file()], "A failed fresh write renames nothing more")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))

func _failed_rename_stays_read_only() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{ interrupted")
	var aside := _aside(path)
	# A directory at the recovery name makes the rename fail.
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(aside))
	var store := Storage.new(path)
	store.load_data()
	_check(not store.start_fresh_if_unreadable() and store.read_only and store.last_error == PlayerCopy.LOCAL_SAVE_34FCC2945DC1, "A failed rename keeps today's read-only hold")
	_check(FileAccess.get_file_as_string(path) == "{ interrupted", "A failed rename leaves the damaged file in place")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aside))
	store.load_data()
	_check(store.start_fresh_if_unreadable() and FileAccess.get_file_as_string(aside) == "{ interrupted", "The next launch finishes the move")

func _main_shows_note_once() -> void:
	var directory := _directory()
	var path := directory.path_join("journey.json")
	_write(path, "{ interrupted")
	var app := Main.new()
	app.saves = Storage.new(path)
	root.add_child(app)
	_check(app.toast.visible and app.toast.text == PlayerCopy.LOCAL_SAVE_STARTED_FRESH, "The app shows the note at launch")
	_check(not app.saves.read_only and app.saves.update_values({"settings": _flipped(app.saves.data.settings)}), "A toggle saves after the fix")
	app.queue_free()
	await process_frame
	await process_frame
	var again := Main.new()
	again.saves = Storage.new(path)
	root.add_child(again)
	_check(again.toast.text != PlayerCopy.LOCAL_SAVE_STARTED_FRESH and not again.saves.data.settings.sound, "The next launch keeps the toggle and shows no note")
	_check(_files(directory).filter(func(name: String) -> bool: return name.contains(Storage.UNREADABLE)).size() == 1, "The next launch moves nothing more")
	again.queue_free()
	await process_frame
	await process_frame

func _flipped(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(true)
	result.sound = false
	return result

func _remove_tree(directory: String) -> void:
	for name: String in DirAccess.get_directories_at(directory): _remove_tree(directory.path_join(name))
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
