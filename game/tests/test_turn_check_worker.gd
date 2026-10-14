extends SceneTree
## The check of a finished solo turn replays the whole turn; at the end of a
## long turn that took seconds in one frame. It now runs on a worker while the
## wait card is up (relay_preview._start_turn_check), and the review and Save
## that follow reuse it.
## - A worker's check is exactly verify_turn's own result, and once taken the
##   journey has nothing left to check for that turn.
## - A check made where the journey no longer stands is never kept.
## - The chapter screen ends a turn with the check on its worker and the wait
##   card up, then shows the review with the check already made.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Preview = preload("res://cooperative_preview.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://turn-check-worker-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for chapter: String in [Registry.CONSERVATORY, Registry.WISHING_WELL, Registry.FIRST_STEPS]:
		_worker_matches(chapter)
	_stale_job_is_dropped(Registry.WISHING_WELL)
	await _screen_checks_on_worker(Registry.CONSERVATORY)
	print("TURN CHECK WORKER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

static func _input(t: int) -> Dictionary:
	return {"move_x": sin(t * 0.045) * 0.9, "move_z": cos(t * 0.031) * 0.9, "interact": t % 150 == 75}

func _fixture(name: String) -> Dictionary:
	for folder: String in ["journey", "cooperative", "first_steps"]:
		var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

func _played(journey: Journey) -> Dictionary:
	var live: RefCounted = journey.create_live_simulation(false)
	var t := 0
	while not live.finished and t < 2000:
		t += 1
		live.step(_input(t))
	return live.export_recording()

func _worker_matches(chapter: String) -> void:
	var path := directory.path_join(chapter.validate_filename() + ".json")
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	var recording := _played(journey)
	var job: Dictionary = journey.turn_check_job(recording)
	_check(not job.is_empty(), chapter + ": a finished turn has a check to run")
	var thread := Thread.new()
	thread.start(Callable(Journey, "run_turn_check").bind(job))
	var result: Dictionary = thread.wait_to_finish()
	journey.adopt_turn_check(job, result)
	_check(journey.turn_check_job(recording).is_empty(), chapter + ": once taken, nothing is left to check for that turn")
	_check(journey.expected_wait_usec() >= int(result.usec), chapter + ": the worker's time sets the next wait estimate")
	var direct := Journey.new(path, null, chapter)
	direct.load_data()
	var expected := var_to_bytes(direct.verify_turn(recording))
	_check(var_to_bytes(journey.verify_turn(recording)) == expected and var_to_bytes(result.checked) == expected, chapter + ": the worker's check is exactly verify_turn's own result")

func _stale_job_is_dropped(chapter: String) -> void:
	var journey := Journey.new(directory.path_join("stale.json"), null, chapter)
	journey.load_data()
	var recording := _played(journey)
	var job: Dictionary = journey.turn_check_job(recording)
	var result := Journey.run_turn_check(job)
	_check(journey.accept_recording(_fixture(str(journey._level.stages[0].id) + "-a")), chapter + ": a first turn is saved meanwhile (" + journey.last_error + ")")
	journey.adopt_turn_check(job, result)
	_check(journey._verified_turns.is_empty() or not journey._verified_turns.has(str(job.key)), chapter + ": a check made where the journey no longer stands is not kept")

func _screen_checks_on_worker(chapter: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var screen := Preview.new()
	screen.chapter_key = chapter
	screen.journey = Journey.new(directory.path_join("screen.json"), null, chapter)
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(screen)
	screen.set_physics_process(false)
	for frame in range(3): await process_frame
	screen._begin()
	var t := 0
	while screen.running and t < 2000:
		t += 1
		screen.advance_input(_input(t))
	_check(not screen.running and screen._check_thread != null, chapter + " screen: the finished turn's check runs on its worker")
	_check(screen.mode in ["turn_wait", "bloom"], chapter + " screen: the wait card (or the bloom) is up while it runs (" + screen.mode + ")")
	var guard := 0
	var frames := 0
	while screen.mode != "review" and guard < 3000:
		if screen.mode == "bloom": screen._process(Preview.COMPLETION_DURATION)
		await process_frame
		frames += 1
		guard += 1
	_check(screen.mode == "review" and screen._check_thread == null, chapter + " screen: the review follows the check")
	_check(frames >= 2, chapter + " screen: frames kept drawing while the turn was checked (%d)" % frames)
	_check(screen.journey.turn_check_job(screen.review).is_empty(), chapter + " screen: the review and its Save find the check made")
	viewport.queue_free()
	for frame in range(3): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
