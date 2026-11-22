extends SceneTree
## A Sleeping Lighthouse @1 journey that converts, but whose @2 journal cannot
## be written on that first open (full disk, I/O), is not marked as one that
## did not convert: the screen says the save failed and the next open carries
## it over. Before, a finished journey was marked "fresh" and @2 started empty
## for good; an unfinished one was sent back to the @1 screen. The journey is
## the first stage's light pad turn: since @2's mirrors went solid, a turn
## that works a mirror no longer converts (test_lighthouse_v2_release).
const Registry = preload("res://services/chapter_registry.gd")
const Migration = preload("res://services/lighthouse_migration.gd")
const V1Journey = preload("res://services/lighthouse_journey.gd")
const KEY := Registry.LIGHTHOUSE_V2

var checks := 0
var failures := 0
var frozen: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	frozen = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/complete-six-v3.json"))
	var v2 := str(Registry.descriptor(KEY).local_path)
	for path: String in [Migration.V1_PATH, v2, Migration.MARKER_PATH]: _remove(path)
	_v1(Migration.V1_PATH)
	_check(Migration.plan() == "migrate", "An @1 journey and no @2 save plan a carry-over")
	# The @2 journal cannot be written: its new copy's place is taken.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v2 + ".tmp"))
	var scene := _open()
	_check(await _wait_mode(scene, ["ready", "complete", "error", "leaving"]), "The first open settles")
	_check(scene.mode == "error", "A carry-over that could not be saved says so instead of opening an empty @2: " + str(scene.mode))
	_check(Migration.plan() == "migrate", "...and is tried again on the next open: " + Migration.plan())
	await _close(scene)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v2 + ".tmp"))
	scene = _open()
	_check(await _wait_mode(scene, ["ready", "complete", "error", "leaving"]) and scene.mode == "ready", "With room to write, the next open shows the carried-over turn: " + str(scene.mode))
	_check(scene.journey.pairs().is_empty() and scene.journey.role() == "b", "...with the @1 light pad turn carried over")
	await _close(scene)
	for path: String in [Migration.V1_PATH, v2, Migration.MARKER_PATH]: _remove(path)
	print("LIGHTHOUSE MIGRATION WRITE FAILURE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## An @1 journal of the first stage's light pad turn.
func _v1(path: String) -> void:
	var journal := V1Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and journal.accept_recording(frozen.pairs[0].a), "An @1 journal holds the first A turn")

func _open() -> Node:
	var scene: Node = load(Registry.solo_scene(KEY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	return scene

func _close(scene: Node) -> void:
	if not is_instance_valid(scene): return
	scene._leaving = true
	scene.queue_free()
	await process_frame

func _wait_mode(scene: Node, modes: Array, seconds: float = 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while is_instance_valid(scene) and scene.mode not in modes and Time.get_ticks_msec() < deadline: await process_frame
	return is_instance_valid(scene) and scene.mode in modes

func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
