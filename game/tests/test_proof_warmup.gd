extends SceneTree
## Saved solo journeys are proved ahead on one worker while Home is idle. The
## proofs it remembers are byte-identical to the full chain check, a stop
## request ends it between stages (keeping finished stages), backgrounding
## stops it, and leaving the tree or quitting mid-run hands the worker to the
## shared reaper instead of waiting or leaking it.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Warmup = preload("res://services/journey_proof_warmup.gd")
const Reaper = preload("res://services/worker_reaper.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _run() -> void:
	directory = "user://proof-warmup-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	Proofs.directory = directory.path_join("proofs")
	await _proves_ahead()
	await _starts_when_idle()
	await _stops_between_stages()
	# Left running at quit: its node leaves the tree during quit and hands the
	# worker to the reaper, which joins it before the scripts are freed.
	var at_quit := _warmup([_tide_save("quit")])
	_check(at_quit.start() and at_quit.running(), "A warm-up is still running at quit")
	print("PROOF WARMUP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Proofs made ahead equal the full check byte for byte, and the next open of
## that save reuses them.
func _proves_ahead() -> void:
	_forget()
	var saves: Array = []
	var expected: Array = []
	for spec: Array in [[Registry.WISHING_WELL, 1], [Registry.LONG_WAY_HOME_V2, 1]]:
		var state := _state(str(spec[0]), int(spec[1]), "b")
		var path := _write(str(spec[0]), state, "ahead")
		saves.append({"chapter": spec[0], "path": path})
		expected.append([spec[0], path, state, Journey.new(path, null, str(spec[0]))._validate_state(state)])
	var warmup := _warmup(saves)
	_check(warmup.start(), "The warm-up starts its worker")
	await _until_done(warmup)
	_check(not warmup.running() and warmup.last_results.size() == 2 and warmup.last_results.all(func(line: String) -> bool: return line.ends_with(": proven")), "Each saved journey is proved: " + str(warmup.last_results))
	for item: Array in expected:
		var journey := Journey.new(str(item[1]), null, str(item[0]))
		var remembered: Dictionary = Proofs.recall(journey, item[2])
		_check(item[3].get("valid", false) and var_to_bytes(remembered.get("checkpoint", {})) == var_to_bytes(item[3].checkpoint), str(item[0]) + ": the proof made ahead equals the full check's checkpoint bytes")
		journey.load_data()
		_check(not journey.read_only and var_to_bytes(journey._checkpoint) == var_to_bytes(item[3].checkpoint), str(item[0]) + ": opening the save afterwards reuses it")
	# A second run finds everything known and replays nothing.
	var again := _warmup(saves)
	again.start()
	await _until_done(again)
	_check(again.last_results.all(func(line: String) -> bool: return line.ends_with(": known")), "A second warm-up finds the proofs remembered: " + str(again.last_results))
	warmup.queue_free()
	again.queue_free()

## Starts only after Home has been idle for a while, and not in the background.
func _starts_when_idle() -> void:
	_forget()
	var idle := [false]
	var warmup := _warmup([{"chapter": Registry.WISHING_WELL, "path": _write(Registry.WISHING_WELL, _state(Registry.WISHING_WELL, 0, "b"), "idle")}])
	warmup.set_process(false)
	warmup.idle = func() -> bool: return idle[0]
	warmup._process(Warmup.IDLE_SECONDS + 1.0)
	_check(not warmup.running(), "Nothing starts while Home is not idle")
	idle[0] = true
	warmup._process(Warmup.IDLE_SECONDS * 0.5)
	_check(not warmup.running(), "Nothing starts before Home has been idle long enough")
	warmup._notification(NOTIFICATION_APPLICATION_PAUSED)
	warmup._process(Warmup.IDLE_SECONDS)
	_check(not warmup.running(), "Nothing starts in the background")
	warmup._notification(NOTIFICATION_APPLICATION_RESUMED)
	warmup._process(Warmup.IDLE_SECONDS * 0.6)
	warmup._process(Warmup.IDLE_SECONDS * 0.6)
	_check(warmup.running(), "It starts once Home has been idle long enough")
	warmup.set_process(true)
	await _until_done(warmup)
	_check(warmup.last_results.size() == 1 and warmup._finished, "It finishes and does not start again: " + str(warmup.last_results))
	warmup.queue_free()

## A stop request (a chapter opening, or the app going to the background)
## ends the worker after its current stage; that stage stays remembered.
func _stops_between_stages() -> void:
	_forget()
	var save := _tide_save("stop")
	var state: Dictionary = Warmup._read(str(save.path))
	var warmup := _warmup([save])
	var started := Time.get_ticks_msec()
	_check(warmup.start(), "A slow warm-up starts")
	await process_frame
	warmup.stop()
	await _until_done(warmup)
	var journey := Journey.new(str(save.path), null, str(save.chapter))
	_check(not warmup.running() and Time.get_ticks_msec() - started < 30000, "A stopped warm-up ends after its current stage (%d ms)" % (Time.get_ticks_msec() - started))
	_check(Proofs.recall(journey, state).is_empty() and not warmup._finished, "A stopped save is not remembered and a later idle Home resumes it: " + str(warmup.last_results))
	_check(Proofs._stages.size() <= 1, "Only the finished stage is kept")
	journey.load_data()
	_check(not journey.read_only and not Proofs.recall(journey, state).is_empty(), "Opening it then proves the rest in the foreground")
	# Backgrounding stops it too.
	_forget()
	var backgrounded := _warmup([save])
	backgrounded.start()
	backgrounded._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _until_done(backgrounded)
	_check(not backgrounded.running() and backgrounded._run == null and not backgrounded._finished, "Going to the background stops it")
	# Leaving the tree mid-run never waits: the reaper takes the worker.
	_forget()
	var leaving := _warmup([save])
	leaving.start()
	var thread: Thread = leaving._thread
	var left := Time.get_ticks_msec()
	root.remove_child(leaving)
	leaving.free()
	_check(Reaper.holds(thread) and Time.get_ticks_msec() - left < 200, "Leaving mid-run hands the worker to the reaper without waiting")
	var deadline := Time.get_ticks_msec() + 30000
	while thread.is_started() and Time.get_ticks_msec() < deadline: await process_frame
	_check(not thread.is_started(), "The reaper joins it once it stops")
	backgrounded.queue_free()
	warmup.queue_free()

func _warmup(saves: Array) -> Node:
	var warmup := Warmup.new()
	warmup.sources = saves
	warmup.idle = func() -> bool: return false
	root.add_child(warmup)
	return warmup

func _until_done(warmup: Node) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while warmup.running() and Time.get_ticks_msec() < deadline: await process_frame

func _tide_save(label: String) -> Dictionary:
	var chapter := Registry.TURN_OF_THE_TIDE
	return {"chapter": chapter, "path": _write(chapter, _state(chapter, 1, "b"), label)}

func _state(chapter: String, prefix: int, role: String) -> Dictionary:
	var level := Registry.definition(chapter)
	var state: Dictionary = Journey.new(directory.path_join("template.json"), null, chapter)._empty_state()
	for index in range(prefix):
		state.pairs.append({"a": _fixture(chapter, str(level.stages[index].id), "a"), "b": _fixture(chapter, str(level.stages[index].id), "b")})
	if role == "b": state.a = _fixture(chapter, str(level.stages[prefix].id), "a")
	return state

func _write(chapter: String, state: Dictionary, label: String) -> String:
	var path := directory.path_join((chapter + "-" + label + "-" + Crypto.new().generate_random_bytes(3).hex_encode()).validate_filename() + ".json")
	var journey := Journey.new(path, null, chapter)
	journey._storage.load_data()
	_check(journey._storage.update_values({"relay": state.duplicate(true)}), "A fixture save is written")
	return path

func _forget() -> void:
	Proofs._mutex.lock()
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	Proofs._mutex.unlock()
	if not DirAccess.dir_exists_absolute(Proofs.directory): return
	for name: String in DirAccess.get_files_at(Proofs.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory.path_join(name)))

func _fixture(chapter: String, stage: String, role: String) -> Dictionary:
	var level := Registry.definition(chapter)
	var prefixes := [""]
	if int(level.get("version", 1)) > 1: prefixes.push_front("%s-v%d-" % [level.id, int(level.version)])
	for folder: String in ["cooperative", "journey"]:
		for prefix: String in prefixes:
			var path := "res://tests/fixtures/%s/%s%s-%s.json" % [folder, prefix, stage, role]
			if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}
