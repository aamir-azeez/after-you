extends SceneTree
## Reopening a finished solo chapter sets up its final scene from the journey's
## proven checkpoint before the last stage and replays only that turn, on a
## worker behind the wait card (RelayJourney.final_scene_job and
## build_final_scene, relay_preview._start_final_scene). It used to replay and
## prove every stage again in one frame: seconds, more for longer chapters.
## - The worker's final scene is exactly the one the full replay builds.
## - The screen shows the wait card, keeps drawing frames, then the completion
##   card on that scene; a journey without the proof is rebuilt as before.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _fixture(name: String) -> Dictionary:
	for folder: String in ["journey", "cooperative"]:
		var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

func _run() -> void:
	directory = "user://final-scene-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	await _chapter(Registry.WISHING_WELL, true)
	await _chapter(Registry.TURN_OF_THE_TIDE, false)
	print("FINAL SCENE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _finished(key: String) -> String:
	var path := directory.path_join(key.validate_filename() + ".json")
	var journey := Journey.new(path, null, key)
	journey.load_data()
	var ok := true
	for stage: Dictionary in Registry.definition(key).stages:
		ok = ok and journey.accept_recording(_fixture(str(stage.id) + "-a")) and journey.accept_recording(_fixture(str(stage.id) + "-b"))
	_check(ok and journey.chapter_complete(), key + ": a finished journey to reopen (" + journey.last_error + ")")
	return path

## The scene the screen used to rebuild: every stage replayed and proved.
func _full_replay(key: String, pairs: Array) -> RefCounted:
	var definition := Registry.definition(key)
	var family := Registry.simulation_script(key)
	var simulation: RefCounted = family.new()
	var start: Dictionary = Registry.initial_checkpoint(key)
	for pair: Dictionary in pairs:
		if not simulation.reset(definition, str(pair.b.stage_id), start, pair.a, "b"): return null
		simulation.catch_assistance = bool(pair.b.catch_assistance)
		for input: Dictionary in family.expand_recording_inputs(pair.b): simulation.step(input)
		start = family.derive_checkpoint(definition, start, pair.a, pair.b).checkpoint
	return simulation

func _chapter(key: String, compare_full: bool) -> void:
	var path := _finished(key)
	var journey := Journey.new(path, null, key)
	journey.load_data()
	var job: Dictionary = journey.final_scene_job()
	_check(not job.is_empty(), key + ": a finished journey has its final scene to set up")
	var built: Dictionary = Journey.build_final_scene(job)
	_check(built.get("ok", false), key + ": the final turn sets up from the proven checkpoint and replays")
	if compare_full:
		var full := _full_replay(key, journey.pairs())
		_check(full != null and var_to_bytes(built.simulation.snapshot()) == var_to_bytes(full.snapshot()) and built.simulation.state_hash() == full.state_hash(), key + ": the same final scene as replaying every stage")
	var unfinished := Journey.new(directory.path_join("unfinished.json"), null, key)
	unfinished.load_data()
	_check(unfinished.final_scene_job().is_empty(), key + ": an unfinished journey has no final scene job")
	# The screen.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	screen.journey = Journey.new(path, null, key)
	var board_asks: Array = []
	if "board_line" in screen:
		screen.board_line = func(_snapshot: Dictionary, asked: String) -> Control:
			board_asks.append(asked)
			return null
	viewport.add_child(screen)
	_check(screen.mode == "turn_wait" and screen._scene_thread != null, key + " screen: the wait card is up while the final scene is set up on its worker")
	var frames := 0
	while screen.mode != "complete" and frames < 3000:
		await process_frame
		frames += 1
	_check(screen.mode == "complete" and frames >= 2 and screen._scene_thread == null, key + " screen: the completion card follows, frames kept drawing (%d)" % frames)
	_check(var_to_bytes(screen.sim.snapshot()) == var_to_bytes(built.simulation.snapshot()), key + " screen: it shows the final scene the worker built")
	_check(board_asks.is_empty(), key + " screen: a solo finish has no leaderboard line")
	# Right after Save the screen's own turn is reused, but only when that turn
	# started where the last pair did. A room's snapshot can change under a
	# turn: then the worker sets the scene up from the proven checkpoint again.
	var last: Dictionary = screen.journey.pairs()[-1]
	var proof: Dictionary = screen.journey.checkpoint().get("proof", {})
	screen.prior = last.a.duplicate(true)
	screen.checkpoint = proof.get("checkpoint", {}).duplicate(true)
	screen._show_completed()
	_check(screen.mode == "complete" and screen._scene_thread == null, key + " screen: a turn that started at the last pair's checkpoint is reused")
	screen.checkpoint = Registry.initial_checkpoint(key)
	screen.sim = built.simulation
	screen._show_completed()
	_check(screen.mode == "turn_wait" and screen._scene_thread != null, key + " screen: a turn that started from another checkpoint is not reused; the worker sets the scene up")
	frames = 0
	while screen.mode != "complete" and frames < 3000:
		await process_frame
		frames += 1
	_check(screen.mode == "complete" and var_to_bytes(screen.sim.snapshot()) == var_to_bytes(built.simulation.snapshot()), key + " screen: ...and the completion card shows the proven final scene")
	viewport.queue_free()
	for frame in range(3): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
