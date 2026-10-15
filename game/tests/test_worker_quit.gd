extends SceneTree
## Quitting while background checks still run. Owners leaving the tree at quit
## hand their running workers to the shared reaper, and the reaper joins them
## before the scripts they run are freed. Leaving the tree is checked directly
## (the worker must reach the reaper, which must already be in the tree); the
## real quit then tears down with workers still running and must exit cleanly,
## with no "Thread object is being destroyed without its completion".
## A worker a coroutine awaits (worker_reaper.run) belongs to the reaper from
## its start: a room coordinator dropped while its Lighthouse proof runs (a
## room closing at quit) leaves the proof running with the reaper, never
## destroyed with the dropped coroutine. That proof is held to always outlast
## quit; a destroyed one crashed the exit (0xC0000005), so the exit code is
## the check.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Preview = preload("res://relay_preview.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Solo = preload("res://services/solo_replay_collection.gd")
const Reaper = preload("res://services/worker_reaper.gd")

var checks := 0
var failures := 0
var directory := ""

## A room coordinator whose proof ahead always outlasts quit, then proves.
class SlowProofRoom extends "res://services/relay_room_coordinator.gd":
	static func _prove_checkpoint(engine: Script, level: Dictionary, checkpoint: Dictionary) -> bool:
		OS.delay_msec(2500)
		return engine.verify_checkpoint(level, checkpoint).get("valid", false)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://worker-quit-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	_check(Reaper.pending_count() == 0 and root.get_node_or_null(Reaper.NODE_NAME) == null, "No reaper exists before any worker starts")
	# A solo chapter screen leaving while its next turn is still being set up,
	# as quitting removes it from the tree: the worker goes to the reaper.
	var left := await _screen_setting_up("left")
	var left_thread: Thread = left._prefetch_thread
	root.remove_child(left)
	left.free()
	_check(Reaper.holds(left_thread), "A screen leaving mid-setup hands its running worker to the reaper")
	# Another such screen stays in the tree and leaves during the real quit.
	var app := await _screen_setting_up("stays")
	var held: Thread = app._prefetch_thread
	# Solo replays on Main with its verifier waiting for more sources.
	var main := Main.new()
	main.saves = Storage.new(directory + "/save.json")
	main.saves.data.settings.sound = false
	root.add_child(main)
	await process_frame
	main.solo_replays = Solo.new(_seed_relay(), "")
	main.solo_replays.begin_scan()
	var deadline := Time.get_ticks_msec() + 20000
	while main.solo_replays._worker == null and main.solo_replays.scan_pending() and Time.get_ticks_msec() < deadline:
		main.solo_replays.advance_scan()
		if main.solo_replays._worker == null: await process_frame
	_check(main.solo_replays._worker != null and main.solo_replays._worker.is_started(), "The Solo scan's verifier was started and is not joined yet")
	var reaper: Node = root.get_node_or_null(Reaper.NODE_NAME)
	_check(reaper != null and reaper.is_inside_tree(), "Starting a worker set the reaper up in the tree before quit")
	# A room coordinator proving a late-joined Lighthouse room ahead awaits its
	# worker in a coroutine; the room closes (the coordinator is dropped)
	# while the proof runs.
	var coordinator: RefCounted = SlowProofRoom.new(Callable(), Callable(), Callable(), Callable())
	coordinator._prove_room_ahead({"ok": true, "data": _late_room()})
	coordinator = null
	_check(await Reaper.run(Callable(get_script(), "_sum").bind(2, 3)) == 5, "An awaited worker hands its result back to a caller still there")
	_check(held.is_alive(), "A next-turn setup is still running at quit")
	print("WORKER QUIT: %d checks, %d failures" % [checks, failures])
	# Both owners leave the tree during quit; the reaper joins their workers.
	quit(1 if failures else 0)

## A Relay screen at the review of its first turn, its next-turn prefetch
## swapped for the same job held up long enough to outlast quit.
func _screen_setting_up(name: String) -> Node:
	var app := Preview.new()
	app.journey = Journey.new(directory + "/relay-" + name + ".json")
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	app._begin()
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-a")): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	for frame in range(30):
		if app.mode == "review": break
		await process_frame
	_check(app.mode == "review" and not app._prefetch_job.is_empty(), name + ": the review starts setting up the next turn on a worker")
	var job: Dictionary = app._prefetch_job.duplicate(true)
	app._drop_prefetch()
	var held := Thread.new()
	_check(held.start(Callable(get_script(), "_slow_build").bind(job)) == OK, name + ": a slow next-turn setup starts")
	app._prefetch_thread = held
	app._prefetch_job = job
	return app

static func _sum(first: int, second: int) -> int:
	return first + second

## A stage-five Lighthouse room as a late joiner first reads it.
func _late_room() -> Dictionary:
	var chain := _fixture("lighthouse/v2-chain")
	var known := Registry.descriptor(Registry.LIGHTHOUSE_V2)
	return {"level_id": known.level_id, "level_version": known.level_version, "definition_hash": known.definition_hash, "checkpoint": chain.checkpoints[5]}

static func _slow_build(job: Dictionary) -> Dictionary:
	OS.delay_msec(1500)
	return Journey.build_live(job)

## A completed Relay journal from the published fixtures.
func _seed_relay() -> Dictionary:
	var path := directory + "/relay-solo.json"
	var level := Registry.definition(Registry.RELAY)
	var validator := Journey.new(path, null, Registry.RELAY)
	for rules: Variant in Registry.supported_rules(Registry.RELAY):
		var pairs: Array = []
		for stage: Dictionary in level.stages:
			pairs.append({"a": _fixture("v2/" + str(stage.id) + "-a"), "b": _fixture("v2/" + str(stage.id) + "-b")})
		var state := {"schema_version": level.schema_version, "simulation_version": int(rules), "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "pairs": pairs, "a": {}, "draft": {}}
		if validator._validate_state(state).get("valid", false):
			var envelope := Storage.defaults()
			envelope.generation = 1
			envelope["relay"] = state
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify(envelope))
			file.close()
			break
	_check(FileAccess.file_exists(path), "A complete Relay journal is seeded")
	return {Registry.RELAY: path}

func _fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/" + name + ".json"
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
