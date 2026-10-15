extends SceneTree
## Leaving Home never waits for Home's keepsake check: deactivate() hands a
## check still running to the shared reaper (worker_reaper.gd), which joins it
## once it ends. It used to wait 1-2 s for a long saved journey's check.
## - deactivate() returns while the check runs, asks it to stop after its
##   current stage, the reaper holds it, and later joins it; nothing it found
##   is awarded after Home went away.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Proofs = preload("res://services/journey_proofs.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _fixture(name: String) -> Dictionary:
	for folder: String in ["journey", "cooperative"]:
		var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

func _run() -> void:
	var directory := "user://keepsake-leave-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	# A Turn of the Tide save with a finished first stage: its check replays
	# that stage and the next first turn, long enough to still be running.
	var chapter := Registry.TURN_OF_THE_TIDE
	var path := directory.path_join("tide.json")
	var journal := Journey.new(path, null, chapter)
	journal.load_data()
	var level: Dictionary = journal._level
	_check(journal.accept_recording(_fixture(str(level.stages[0].id) + "-a")) and journal.accept_recording(_fixture(str(level.stages[0].id) + "-b")), "A saved first stage to check")
	# Nothing proven yet (as after an update): the check replays the stage.
	var proofs_before := Proofs.directory
	Proofs.directory = directory.path_join("proofs")
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	var ledger := Keepsakes.new(directory.path_join("keepsakes.json"), null, {chapter: path})
	ledger.activate()
	ledger.reconcile_solo()
	var guard := 0
	while ledger._worker == null and guard < 50:
		ledger.advance_backfill(1)
		guard += 1
	var worker: Thread = ledger._worker
	var stop: RefCounted = ledger._worker_stop
	_check(worker != null and worker.is_alive(), "Home's keepsake check is running")
	var before := ledger.earned_descriptors()
	var started := Time.get_ticks_msec()
	ledger.deactivate()
	var waited := Time.get_ticks_msec() - started
	_check(ledger._worker == null and Reaper.holds(worker), "Leaving Home hands the running check to the reaper")
	_check(worker.is_alive() or waited < 50, "Leaving Home did not wait for the check (%d ms)" % waited)
	_check(stop != null and stop.stopped(), "Leaving Home asks the check to stop after its current stage")
	ledger = null
	var deadline := Time.get_ticks_msec() + 60000
	while Reaper.holds(worker) and Time.get_ticks_msec() < deadline: await process_frame
	_check(not Reaper.holds(worker) and not worker.is_started(), "The reaper joins the check once it ends")
	var after := Keepsakes.new(directory.path_join("keepsakes.json"), null, {chapter: path})
	_check(after.earned_descriptors() == before, "Nothing the abandoned check found was awarded after Home went away")
	Proofs.directory = proofs_before
	print("KEEPSAKE LEAVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
