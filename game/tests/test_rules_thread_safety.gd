extends SceneTree
## Background replay checks run the same chapter rules as the scene on the main
## thread. This suite runs the three production worker paths (Together shared
## replays, Home keepsakes backfill, Earlier islands replay preparation) on
## their own threads while the main thread steps and verifies the same chapter
## families, and requires every result to match a serial run exactly. It then
## frees each owner of a background check mid-check and requires the join: by
## the owner itself, or by the shared reaper for a screen that leaves.
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Collection = preload("res://services/shared_replay_collection.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const LoadProgress = preload("res://services/replay_load_progress.gd")
const Main = preload("res://main.gd")
const Solo = preload("res://services/solo_replay_collection.gd")
const View = preload("res://presentation/shared_replay_view.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const EarlierIslandReplay = preload("res://services/earlier_island_replay.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const FAMILIES := [
	[Registry.WISHING_WELL, "cooperative/go-on-ahead-checkpoint"],
	[Registry.LONG_WAY_HOME, "journey/the-path-you-leave-checkpoint"],
	[Registry.TURN_OF_THE_TIDE, "journey/set-the-tide-half-checkpoint"],
]
## Main-thread stress time; the main thread runs at least MIN_ROUNDS and each
## worker keeps checking until it ends. AFTER_YOU_STRESS_MSEC sets a longer soak.
const MAIN_MSEC := 6000
const MIN_ROUNDS := 2
## Kept low so the suite fits CI's per-suite limit on a slow runner.
const MIN_WORKER_ROUNDS := 1
var checks := 0
var failures := 0
var _stop_mutex := Mutex.new()
var _stop := false

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var clock := Time.get_ticks_msec()
	var inputs := _inputs()
	var expected := _serial(inputs)
	var serial_ms := Time.get_ticks_msec() - clock
	_check(expected.together.size() == inputs.together.size() and expected.keepsakes.size() == inputs.keepsakes.size(), "Serial baseline covers every worker input")
	for key: String in expected.valid:
		print("serial %s valid=%s" % [key, expected.valid[key]])
	_check(expected.valid.get(Registry.WISHING_WELL, false) and expected.valid.get(Registry.LONG_WAY_HOME, false) and expected.valid.get("legacy", false), "Serial baseline replays cooperative, journey and legacy proofs as valid")
	var workers: Array = []
	for path: Array in [["together", _together_loop], ["keepsakes", _keepsakes_loop], ["earlier", _earlier_loop]]:
		var thread := Thread.new()
		# Each worker receives its own deep copies, as the production paths do.
		var started := thread.start(Callable(path[1]).bind(inputs.duplicate(true), expected.duplicate(true)))
		_check(started == OK, "The %s worker starts" % path[0])
		if started == OK: workers.append([path[0], thread])
	var live := _live_inputs()
	var began := Time.get_ticks_msec()
	var main_rounds := 0
	var main_mismatch := 0
	var budget := int(OS.get_environment("AFTER_YOU_STRESS_MSEC")) if OS.get_environment("AFTER_YOU_STRESS_MSEC").is_valid_int() else MAIN_MSEC
	while Time.get_ticks_msec() - began < budget or main_rounds < MIN_ROUNDS:
		for item: Dictionary in live:
			if _live_digest(item) != item.expected: main_mismatch += 1
		# One family's full checkpoint check per round, in turn, on the main thread too.
		var family: String = FAMILIES[main_rounds % FAMILIES.size()][0]
		if bool(Registry.simulation_script(family).verify_checkpoint(Registry.definition(family), inputs.checkpoints[family]).valid) != bool(expected.valid[family]): main_mismatch += 1
		main_rounds += 1
	_stop_mutex.lock()
	_stop = true
	_stop_mutex.unlock()
	_check(main_mismatch == 0, "Main-thread simulations and checks match the serial run while workers check the same families (%d rounds)" % main_rounds)
	for worker: Array in workers:
		var result: Dictionary = worker[1].wait_to_finish()
		print("%s worker rounds=%d mismatches=%d" % [worker[0], int(result.get("rounds", 0)), int(result.get("mismatch", -1))])
		_check(int(result.get("rounds", 0)) >= MIN_WORKER_ROUNDS, "The %s worker ran concurrently with the main thread" % worker[0])
		_check(int(result.get("mismatch", -1)) == 0, "Every %s worker result matches the serial run" % worker[0])
	var stress_ms := Time.get_ticks_msec() - clock - serial_ms
	await _lifecycle(inputs)
	print("timing ms: serial %d, concurrent %d (%d main rounds), lifecycle %d" % [serial_ms, stress_ms, main_rounds, Time.get_ticks_msec() - clock - serial_ms - stress_ms])
	print("Rules thread safety: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _stopped() -> bool:
	_stop_mutex.lock()
	var value := _stop
	_stop_mutex.unlock()
	return value

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))

## Accepted pairs in order, read from a checkpoint's proof chain.
static func _pairs(checkpoint: Dictionary) -> Array:
	var pairs: Array = []
	var current := checkpoint
	while int(current.get("stage_index", 0)) > 0:
		pairs.push_front({"a": current.proof.a, "b": current.proof.b})
		current = current.proof.checkpoint
	return pairs

func _inputs() -> Dictionary:
	var value := {"checkpoints": {}, "together": [], "keepsakes": [], "earlier": {}}
	for family: Array in FAMILIES:
		var key: String = family[0]
		var checkpoint := _fixture(family[1])
		value.checkpoints[key] = checkpoint
		# Together: one pair entry exactly as the shared replay library stores it.
		var index := int(checkpoint.stage_index) - 1
		var pair := {"pair_id": "p0-%d" % index, "branch": 0, "stage_index": index, "a": checkpoint.proof.a, "b": checkpoint.proof.b, "checkpoint": checkpoint}
		value.together.append({"family": key, "entry": {"schema_version": 1, "room": {"family": "chapter", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": key, "title": "Saved chapter"}, "pair": pair}})
		# Home keepsakes: an archived solo journal with every accepted pair.
		var level := Registry.definition(key)
		var state := {"schema_version": level.schema_version, "simulation_version": int(checkpoint.proof.a.simulation_version), "level_id": level.id, "level_version": level.version,
			"definition_hash": Canonical.digest(level), "pairs": _pairs(checkpoint), "a": {}, "draft": {}}
		var raw := JSON.stringify({"archive_version": 1, "relay": state})
		value.keepsakes.append({"family": key, "snapshot": {"kind": "archive", "chapter": key, "path": "user://unused", "archive_id": Canonical.digest(JSON.parse_string(raw).relay), "raw": [raw]}})
	var a := _fixture("after-you-a")
	var b := _fixture("after-you-b")
	value.together.append({"family": "legacy", "entry": {"schema_version": 1, "room": {"family": "legacy", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": "", "title": "Earlier islands"},
		"pair": {"attempt": 1, "level_id": "after-you", "first_player_id": HOST, "a": a, "b": b}}})
	value.keepsakes.append({"family": "legacy", "snapshot": {"kind": "legacy", "id": "earlier/after-you", "level_id": "after-you", "attempt": {"a": a, "b": b}}})
	value.earlier = {"definition": Levels.get_level("after-you"), "attempt": {"a": a, "b": b, "draft": {}}, "recording": b, "version": int(b.simulation_version)}
	return value

## Exactly what each worker path returns, computed with no other thread running.
func _serial(inputs: Dictionary) -> Dictionary:
	var value := {"valid": {}, "together": [], "keepsakes": [], "earlier": ""}
	# A pair entry replays the whole chain to its checkpoint, so its result is
	# also that checkpoint's validity.
	for item: Dictionary in inputs.together:
		value.together.append(Collection._verify_entry_proof(item.entry.duplicate(true)))
		value.valid[item.family] = value.together[-1]
	for item: Dictionary in inputs.keepsakes:
		value.keepsakes.append(Canonical.digest(Keepsakes._verify_source_snapshot(item.snapshot.duplicate(true), _validator(item.family))))
	value.earlier = _earlier_digest(EarlierIslandReplay.prepare(inputs.earlier.duplicate(true), LoadProgress.new()))
	return value

static func _validator(family: String) -> RefCounted:
	return null if family == "legacy" else RelayJourney.new("user://unused-%s.json" % family.get_slice("@", 0), null, family)

static func _earlier_digest(result: Dictionary) -> String:
	if not result.get("ok", false): return "failed:" + str(result.get("error", ""))
	return Canonical.digest({"frames": result.frames, "state": result.simulation.snapshot()})

func _together_loop(inputs: Dictionary, expected: Dictionary) -> Dictionary:
	var rounds := 0
	var mismatch := 0
	while rounds < MIN_WORKER_ROUNDS or not _stopped():
		for index in range(inputs.together.size()):
			# The uncached proof: what a cold Together library check replays.
			if Collection._verify_entry_proof(inputs.together[index].entry.duplicate(true)) != expected.together[index]: mismatch += 1
		rounds += 1
	return {"rounds": rounds, "mismatch": mismatch}

func _keepsakes_loop(inputs: Dictionary, expected: Dictionary) -> Dictionary:
	var rounds := 0
	var mismatch := 0
	while rounds < MIN_WORKER_ROUNDS or not _stopped():
		for index in range(inputs.keepsakes.size()):
			var item: Dictionary = inputs.keepsakes[index]
			if Canonical.digest(Keepsakes._verify_source_snapshot(item.snapshot.duplicate(true), _validator(item.family))) != expected.keepsakes[index]: mismatch += 1
		rounds += 1
	return {"rounds": rounds, "mismatch": mismatch}

func _earlier_loop(inputs: Dictionary, expected: Dictionary) -> Dictionary:
	var rounds := 0
	var mismatch := 0
	while rounds < MIN_WORKER_ROUNDS or not _stopped():
		if _earlier_digest(EarlierIslandReplay.prepare(inputs.earlier.duplicate(true), LoadProgress.new())) != expected.earlier: mismatch += 1
		rounds += 1
	return {"rounds": rounds, "mismatch": mismatch}

## Live play on the main thread: each family's first stage as the first player,
## stepped with a fixed input pattern. The expected digest is taken before any
## worker starts.
func _live_inputs() -> Array:
	var items: Array = []
	for family: Array in FAMILIES:
		var item := {"key": family[0], "level": Registry.definition(family[0]), "checkpoint": Registry.initial_checkpoint(family[0])}
		item.expected = _live_digest(item)
		items.append(item)
	var level := Levels.get_level("after-you")
	var legacy := {"key": "legacy", "level": level}
	legacy.expected = _live_digest(legacy)
	items.append(legacy)
	return items

static func _live_digest(item: Dictionary) -> String:
	var simulation: RefCounted
	if item.key == "legacy":
		simulation = LegacySimulation.new()
		if not simulation.reset(item.level, {}, "a"): return "reset failed: " + str(simulation.error)
	else:
		simulation = Registry.simulation_script(item.key).new()
		if not Registry.reset_simulation(simulation, item.key, item.level, str(item.level.stages[0].id), item.checkpoint, {}, "a"): return "reset failed: " + str(simulation.error)
	for tick in range(240):
		simulation.step({"x": [60, 0, -40, 20][tick / 60 % 4], "z": [0, 70, 30, -60][tick / 60 % 4], "action": tick % 45 == 0})
	return Canonical.digest(simulation.snapshot())

## A worker must never outlive the service or screen that started it. Engine
## teardown frees the rule scripts under a check that is still running, which
## shows as "Nonexistent function '_entity'" and empty method names at exit, or
## as a crash. Each owner here is released while its real check is in flight;
## the test keeps the Thread object, so it can tell whether the owner joined it.
## RefCounted owners live only in a holder Array and are touched only inside a
## starter function, so no stack temporary keeps one alive past its release.
func _lifecycle(inputs: Dictionary) -> void:
	var entry: Dictionary = {}
	for item: Dictionary in inputs.together:
		if item.family == Registry.LONG_WAY_HOME: entry = item.entry
	var source: Dictionary = {}
	for item: Dictionary in inputs.keepsakes:
		if item.family == Registry.LONG_WAY_HOME: source = item.snapshot
	var holder: Array = []
	_released("Together library", _start_library(holder, entry), holder)
	var view := _start_view(entry)
	await _reaped("Together viewer", view._validation_worker, view)
	_released("Home keepsakes", _start_keepsakes(holder, source), holder)
	_start_solo(holder, source)
	var waited := 0
	while not _solo_posted(holder) and waited < 600:
		waited += 1
		await process_frame
	_released("Solo replays", _solo_worker(holder), holder)
	var app := Main.new()
	app.saves = Storage.new("user://thread-safety-save.json")
	app.saves.data.settings.sound = false
	root.add_child(app)
	for frame in range(3): await process_frame
	await _reaped("Earlier islands", _start_earlier(app, inputs.earlier), app)
	_released("Lighthouse loader", _start_lighthouse(holder), holder)

static func _identity() -> Dictionary:
	return {"ready": true, "player_id": HOST, "epoch": 1}

## Together library: the cold room check for one saved Long Way Home pair, as
## advance_local_load starts it.
func _start_library(holder: Array, entry: Dictionary) -> Thread:
	_forget_proofs()
	var library := Collection.new(null, _identity, null, null)
	holder.append(library)
	var job := {"owner": HOST, "epoch": 1, "generation": 0, "key": "chapter:" + ROOM, "journal": {"ok": true, "found": false}, "raw": false, "online_raw": false, "verified": "", "legacy": {},
		"cached": {"ok": true, "found": true, "value": {"schema_version": 1, "owner": HOST, "entries": {str(entry.pair.pair_id): entry.duplicate(true)}}}, "progress": LoadProgress.new()}
	library._local_job = job
	library._local_worker = Thread.new()
	_check(library._local_worker.start(Callable(Collection, "_verify_local_room").bind(job)) == OK, "Together library worker starts")
	return library._local_worker

## Together viewer: the real loading screen starts its own check on _ready.
func _start_view(entry: Dictionary) -> Node:
	_forget_proofs()
	var view := View.new()
	view.entry = entry.duplicate(true)
	view.sequence = [view.entry]
	view.identity = _identity
	view.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(view)
	_check(view._validation_worker != null, "Together viewer starts its proof check")
	return view

## Home keepsakes: an archived Long Way Home journal through the real worker start.
func _start_keepsakes(holder: Array, source: Dictionary) -> Thread:
	var keepsakes := Keepsakes.new("user://thread-safety-keepsakes.json")
	holder.append(keepsakes)
	_check(keepsakes._start_worker({"kind": "archive", "generation": keepsakes._work_generation, "source": "archive", "fingerprint": ""}, source.duplicate(true), _validator(Registry.LONG_WAY_HOME)), "Home keepsakes worker starts")
	return keepsakes._worker

## Solo replays: a real scan of one archived Long Way Home attempt. The caller
## awaits the frames, so no suspended frame here holds the service.
func _start_solo(holder: Array, source: Dictionary) -> void:
	var path := "user://thread-safety-home.json"
	var archive := FileAccess.open(path + ".attempt-" + str(source.archive_id) + ".json", FileAccess.WRITE)
	archive.store_string(source.raw[0])
	archive.close()
	var solo := Solo.new({Registry.LONG_WAY_HOME: path}, "")
	holder.append(solo)
	solo.begin_scan()

func _solo_posted(holder: Array) -> bool:
	return holder[0]._worker != null or not holder[0].advance_scan()

func _solo_worker(holder: Array) -> Thread:
	_check(holder[0]._worker != null, "Solo replays posts the archived attempt to its verifier")
	return holder[0]._worker

## Earlier islands: the main screen's replay preparation worker.
func _start_earlier(app: Node, earlier: Dictionary) -> Thread:
	Reaper.ensure()
	app.replays_flow._collection_replay_worker = Thread.new()
	_check(app.replays_flow._collection_replay_worker.start(Callable(EarlierIslandReplay, "prepare").bind(earlier.duplicate(true), LoadProgress.new())) == OK, "Earlier islands preparation starts")
	return app.replays_flow._collection_replay_worker

## Lighthouse: the loader's replay-verifying journal load.
func _start_lighthouse(holder: Array) -> Thread:
	var loader := LighthouseLoader.new()
	holder.append(loader)
	_check(loader.start(LighthouseJourney.new("user://thread-safety-lighthouse.json")) == OK, "Lighthouse loader starts")
	return loader._thread

## Releases the owner the way the app does: a screen leaves the tree and is
## freed, a service loses its last reference.
func _released(owner: String, thread: Thread, holder: Array) -> void:
	if thread == null:
		_check(false, owner + " has a worker to release")
		holder.clear()
		return
	var node: Node = holder[0] if holder[0] is Node else null
	holder.clear()
	if node != null:
		node.get_parent().remove_child(node)
		node.free()
	var joined := not thread.is_started()
	_check(joined, owner + " joins its worker before it is freed")
	# Never leave a running check behind this suite, even when the owner failed to.
	if not joined: thread.wait_to_finish()

## A screen that leaves mid-check does not wait for its worker in that frame:
## it asks the check to stop and hands the thread to the shared reaper, which
## joins it once it ends.
func _reaped(owner: String, thread: Thread, node: Node) -> void:
	if thread == null:
		_check(false, owner + " has a worker to release")
		node.free()
		return
	node.get_parent().remove_child(node)
	node.free()
	# Still started: the leaving frame did not join it.
	_check(thread.is_started() and Reaper.holds(thread), owner + " hands its worker to the reaper when it leaves, without joining it in that frame")
	var frames := 0
	var deadline := Time.get_ticks_msec() + 30000
	while thread.is_started() and Time.get_ticks_msec() < deadline:
		frames += 1
		await process_frame
	_check(not thread.is_started(), owner + " worker is joined by the reaper after it ends (%d frames)" % frames)
	if thread.is_started(): thread.wait_to_finish()

func _forget_proofs() -> void:
	Collection._verified_proof_mutex.lock()
	Collection._verified_proofs.clear()
	Collection._verified_proof_mutex.unlock()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
