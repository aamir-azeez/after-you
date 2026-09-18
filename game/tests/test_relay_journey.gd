extends SceneTree

const Journey = preload("res://services/relay_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0
var paths: Array[String] = []
var level := Catalog.relay_isles()
var first_pair: Dictionary = {}
var second_pair: Dictionary = {}
var checkpoint_one: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Journey.PATH != Storage.PATH, "The new chapter uses a distinct file from the original journey")
	if not _prepare_pairs():
		_finish()
		return
	_progression()
	_attempt_forks()
	_rejected_inputs()
	_untrusted_saves()
	_interrupted_generation()
	_truncated_generation()
	_io_failure()
	_live_drafts()
	_timings()
	_finish()


func _prepare_pairs() -> bool:
	var initial := Catalog.initial_checkpoint(level)
	var a := Simulation.new()
	_check(a.reset(level, "relay", initial), "Prepare earlier relay contribution")
	_move(a, Vector2i(-400, 0))
	a.step({"interact": true})
	first_pair.a = a.export_recording()
	_check(a.can_commit(), "Relay A fixture is viable from actual input steps")
	var b := Simulation.new()
	_check(b.reset(level, "relay", initial, first_pair.a, "b"), "Prepare later relay contribution from exact A")
	for tick: int in range(30):
		b.step()
	_move(b, Vector2i(-320, 0))
	_move(b, Vector2i(0, 0))
	_wait_for_seed(b)
	_move(b, Vector2i(40, 0))
	b.step({"interact": true})
	first_pair.b = b.export_recording()
	_check(b.complete and b.can_commit(), "Relay B fixture catches and places the seed through actual input steps")
	var c1 := Simulation.derive_checkpoint(level, initial, first_pair.a, first_pair.b)
	_check(c1.valid, "The first pair produces a verified checkpoint")
	if not c1.valid:
		return false
	checkpoint_one = c1.checkpoint
	a = Simulation.new()
	_check(a.reset(level, "garden", checkpoint_one), "Prepare role-reversed garden stage")
	a.step({"interact": true})
	a.step()
	_move(a, Vector2i(100, 0))
	a.step({"interact": true})
	second_pair.a = a.export_recording()
	_check(a.can_commit(), "Garden A takes the relay seed, moves and throws")
	b = Simulation.new()
	_check(b.reset(level, "garden", checkpoint_one, second_pair.a, "b"), "Prepare garden B from the accepted checkpoint")
	for tick: int in range(20):
		b.step()
	_move(b, Vector2i(-400, 0))
	_move(b, Vector2i(420, 0))
	_wait_for_seed(b)
	_move(b, Vector2i(620, 0))
	_move(b, Vector2i(620, 120))
	b.step({"interact": true})
	second_pair.b = b.export_recording()
	_check(b.complete and b.can_commit(), "Garden B crosses both bridges, catches and plants")
	var complete := Simulation.derive_checkpoint(level, checkpoint_one, second_pair.a, second_pair.b)
	_check(complete.valid and complete.get("checkpoint", {}).get("next_stage_id") == "", "Both exact pairs finish the chapter")
	return complete.valid


func _progression() -> void:
	var path := _path("progress")
	var journey := Journey.new(path)
	journey.load_data()
	_check(not journey.read_only and journey.stage_id() == "relay" and journey.role() == "a", "Fresh chapter starts at verified relay checkpoint/A")
	_check(not FileAccess.file_exists(path), "Reading fresh state alone does not write a file")
	var draft_sim := Simulation.new()
	draft_sim.reset(level, "relay", journey.checkpoint())
	draft_sim.step()
	var incomplete := draft_sim.export_recording()
	_check(journey.save_draft(incomplete), "An authentic incomplete rehearsal can be saved")
	journey = Journey.new(path)
	journey.load_data()
	_check(Canonical.same(journey.draft(), incomplete) and journey.role() == "a", "Restart retains the exact incomplete rehearsal without committing it")
	_check(not journey.accept_recording(incomplete) and journey.pairs().is_empty() and journey.role() == "a", "A valid but unready recording cannot advance progression")
	_check(journey.accept_recording(first_pair.a), "Accept viable A only after a successful save")
	_check(journey.role() == "b" and journey.draft().is_empty() and journey.stage_id() == "relay", "Accepted A changes role but not stage")
	journey = Journey.new(path)
	journey.load_data()
	_check(Canonical.same(journey.prior_recording(), first_pair.a) and journey.role() == "b", "Restart mid-stage keeps the exact earlier recording")
	var b := Simulation.new()
	b.reset(level, "relay", journey.checkpoint(), journey.prior_recording(), "b")
	b.step()
	var b_draft := b.export_recording()
	_check(journey.save_draft(b_draft), "B rehearsal validates against the saved A")
	journey = Journey.new(path)
	journey.load_data()
	_check(Canonical.same(journey.draft(), b_draft) and Canonical.same(journey.prior_recording(), first_pair.a), "Restart with B draft preserves both source and draft")
	_check(journey.save_draft({}) and journey.draft().is_empty() and Canonical.same(journey.prior_recording(), first_pair.a), "Retrying B clears only the rehearsal, never A")
	_check(journey.accept_recording(first_pair.b), "Accept B and persist the completed pair")
	_check(journey.stage_id() == "garden" and journey.role() == "a" and journey.pairs().size() == 1, "One completed pair advances to the next stage/A")
	_check(Canonical.same(journey.checkpoint(), checkpoint_one), "Checkpoint is derived from exact validated recordings")
	_check(journey.checkpoint().players.p0.x == checkpoint_one.players.p0.x and second_pair.a.player_slot == "p1", "Role reversal retains physical p0/p1 positions instead of swapping them")
	var detached: Dictionary = journey.checkpoint()
	detached.players.p0.x = 99999
	var detached_pairs := journey.pairs()
	detached_pairs[0].a.role = "b"
	_check(Canonical.same(journey.checkpoint(), checkpoint_one) and journey.pairs()[0].a.role == "a", "Returned progress dictionaries cannot mutate coordinator state")
	_check(journey.accept_recording(second_pair.a) and journey.accept_recording(second_pair.b), "Accept the second ordered pair")
	_check(journey.chapter_complete() and journey.stage_id().is_empty() and journey.pairs().size() == 2, "Completion follows the verified pair chain")
	var before := FileAccess.get_file_as_string(path)
	_check(not journey.accept_recording(second_pair.b) and not journey.save_draft(second_pair.b), "A complete chapter cannot accept duplicate turns or drafts")
	_check(FileAccess.get_file_as_string(path) == before, "Duplicate completion leaves saved bytes unchanged")
	journey = Journey.new(path)
	journey.load_data()
	_check(not journey.read_only and journey.chapter_complete() and journey.pairs().size() == 2, "Complete chapter survives a new coordinator instance")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(not stored.relay.has("checkpoint") and not stored.relay.has("complete") and not stored.relay.has("role"), "Save contains evidence, not trusted cached progress flags")


func _attempt_forks() -> void:
	var path := _path("fork")
	var storage := ForkFailingStorage.new(path)
	var journey := Journey.new(path, storage)
	journey.load_data()
	for record: Dictionary in [first_pair.a, first_pair.b, second_pair.a, second_pair.b]:
		_check(journey.accept_recording(record), "Archive source accepts verified ordered contributions")
	var completed := journey._state.duplicate(true)
	var bytes_before := FileAccess.get_file_as_string(path)
	_check(not journey.fork_from_stage(-1) and not journey.fork_from_stage(2), "Retry rejects unavailable checkpoints")
	_check(FileAccess.get_file_as_string(path) == bytes_before, "Invalid retry leaves the active journey unchanged")
	storage.reject_write = true
	_check(not journey.fork_from_stage(1) and journey.chapter_complete(), "Failed active-save write leaves the completed journey intact")
	_check(FileAccess.get_file_as_string(path) == bytes_before, "Retry write failure preserves saved progress bytes")
	var archive := path + ".attempt-" + Canonical.digest(completed) + ".json"
	paths.append(archive)
	_check(FileAccess.file_exists(archive), "Write failure retains the safe prior-attempt archive")
	var archive_hash := FileAccess.get_sha256(archive)
	storage.reject_write = false
	_check(journey.fork_from_stage(1) and journey.role() == "a" and journey.stage_id() == "garden", "Retry at stage two creates an immediately playable attempt")
	_check(Canonical.same(journey.pairs(), [first_pair]) and journey.prior_recording().is_empty() and journey.draft().is_empty(), "Retry preserves its exact prefix and clears dependent contributions")
	_check(FileAccess.get_sha256(archive) == archive_hash, "Repeated retry never rewrites the earlier archive")
	_check(journey.archived_attempts().size() == 1 and Canonical.same(journey.archived_pairs(Canonical.digest(completed)), completed.pairs), "Earlier attempts are discoverable and semantically validated after a retry")
	_check(journey.archived_pairs("../other").is_empty(), "Archive reader rejects paths instead of accepting arbitrary file names")
	var forged := completed.duplicate(true)
	forged.pairs[0].b.role = "a"
	var forged_path := path + ".attempt-" + Canonical.digest(forged) + ".json"
	paths.append(forged_path)
	_write(forged_path, JSON.stringify({"archive_version": 1, "relay": forged}))
	_check(journey.archived_pairs(Canonical.digest(forged)).is_empty(), "A valid archive digest does not bypass recording semantics")
	var active_before := FileAccess.get_file_as_string(path)
	_write(archive, "corrupt archive")
	_check(journey.archived_pairs(Canonical.digest(completed)).is_empty() and FileAccess.get_file_as_string(path) == active_before, "Corrupt archived evidence cannot change active progress")

class ForkFailingStorage extends "res://services/local_save.gd":
	var reject_write := false
	func update_values(values: Dictionary, erase_keys: Array = []) -> bool:
		if reject_write:
			last_error = "Injected active retry write failure."
			return false
		return super.update_values(values, erase_keys)

func _rejected_inputs() -> void:
	var path := _path("inputs")
	var journey := Journey.new(path)
	journey.load_data()
	_check(not journey.accept_recording(first_pair.b), "B cannot arrive before A")
	_check(journey.accept_recording(first_pair.a), "Create saved A for source-binding tests")
	var before := FileAccess.get_file_as_string(path)
	var wrong_source: Dictionary = first_pair.b.duplicate(true)
	wrong_source.source_recording_hash = "0".repeat(64)
	wrong_source.recording_hash = Simulation.recording_hash(wrong_source)
	_check(not journey.save_draft(wrong_source) and not journey.accept_recording(wrong_source), "Rehashed draft/commit with a different A source is rejected")
	_check(not journey.accept_recording(second_pair.a), "Another stage cannot overwrite the current accepted A")
	var altered: Dictionary = first_pair.b.duplicate(true)
	altered.final_state_hash = "f".repeat(64)
	altered.recording_hash = Simulation.recording_hash(altered)
	_check(not journey.accept_recording(altered), "Rehashed false final state still fails replay verification")
	_check(FileAccess.get_file_as_string(path) == before and journey.role() == "b", "Rejected candidates do not mutate save or role")


func _untrusted_saves() -> void:
	var template_path := _path("template")
	var good := Journey.new(template_path)
	good.load_data()
	good.accept_recording(first_pair.a)
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(template_path))
	for scenario: String in ["future_nested", "future_envelope", "unknown_field", "false_a", "reordered_pair", "invalid_draft", "foreign_data", "invalid_json"]:
		var path := _path(scenario)
		var data: Dictionary = template.duplicate(true)
		match scenario:
			"future_nested": data.relay.schema_version = 9
			"future_envelope": data.version = 9
			"unknown_field": data.relay.remote_identity = "synthetic-untrusted-field"
			"false_a": data.relay.a.outcome.threw_seed = false
			"reordered_pair":
				data.relay.a = {}
				data.relay.pairs = [second_pair]
			"invalid_draft": data.relay.draft = second_pair.b
			"foreign_data": data.room = {"room_id": "synthetic-foreign-state"}
		var bytes := "{broken" if scenario == "invalid_json" else JSON.stringify(data)
		_write(path, bytes)
		var journey := Journey.new(path)
		journey.load_data()
		_check(journey.read_only and not journey.last_error.is_empty(), scenario + " is held read-only")
		_check(journey.checkpoint().is_empty() and journey.draft().is_empty() and journey.pairs().is_empty(), scenario + " is not used as playable state")
		_check(not journey.save_draft(first_pair.a) and not journey.accept_recording(first_pair.a), scenario + " cannot be overwritten by a new turn")
		_check(FileAccess.get_file_as_string(path) == bytes, scenario + " original bytes remain unchanged")
	# A readable backup must not silently replace unknown future primary data.
	var future_path := _path("future_with_backup")
	var future: Dictionary = template.duplicate(true)
	future.relay.schema_version = 3
	_write(future_path, JSON.stringify(future))
	_write(future_path + ".backup", JSON.stringify(template))
	var held := Journey.new(future_path)
	held.load_data()
	_check(held.read_only and not held.accept_recording(first_pair.b), "Valid older backup cannot overwrite a future primary")


func _interrupted_generation() -> void:
	var path := _path("interrupted")
	var journey := Journey.new(path)
	journey.load_data()
	journey.accept_recording(first_pair.a)
	var primary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var pending: Dictionary = primary.duplicate(true)
	pending.generation += 1
	pending.relay.a = {}
	pending.relay.pairs = [first_pair.duplicate(true)]
	_write(path + ".tmp", JSON.stringify(pending))
	journey = Journey.new(path)
	journey.load_data()
	_check(not journey.read_only and journey.stage_id() == "garden" and journey.pairs().size() == 1, "A valid higher interrupted generation recovers through LocalSave")
	_check(Canonical.same(journey.checkpoint(), checkpoint_one), "Recovered progress is still replay-verified")
	_check(journey.accept_recording(second_pair.a), "Recovered generation can atomically save the next contribution")


func _io_failure() -> void:
	var directory := "user://relay-io-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var path := directory + "/progress.json"
	paths.append(path)
	var journey := Journey.new(path)
	journey.load_data()
	var initial := journey.checkpoint()
	_check(not journey.accept_recording(first_pair.a), "A missing parent directory causes a real write failure")
	_check(journey.role() == "a" and journey.prior_recording().is_empty() and Canonical.same(journey.checkpoint(), initial), "I/O failure cannot advance the role or checkpoint")
	_check(not journey.last_error.is_empty() and not FileAccess.file_exists(path), "Write failure is actionable and produces no false accepted save")
	_check(DirAccess.make_dir_absolute(directory) == OK, "Repair only the isolated test directory")
	_check(journey.accept_recording(first_pair.a) and journey.role() == "b", "Retry after I/O recovery accepts the same real recording")
	_cleanup(path)
	DirAccess.remove_absolute(directory)


func _truncated_generation() -> void:
	for damaged_suffix: String in [".tmp", ""]:
		var path := _path("truncated")
		var journey := Journey.new(path)
		journey.load_data()
		journey.accept_recording(first_pair.a)
		if damaged_suffix.is_empty():
			_check(DirAccess.copy_absolute(path, path + ".backup") == OK, "Keep a valid backup for primary interruption")
		var damaged := path + damaged_suffix
		var damaged_bytes := "{\"version\":1,\"relay\":{"
		_write(damaged, damaged_bytes)
		var archive := damaged + ".unreadable-" + FileAccess.get_sha256(damaged) + ".json"
		paths.append(archive)
		journey = Journey.new(path)
		journey.load_data()
		_check(not journey.read_only and journey.role() == "b" and Canonical.same(journey.prior_recording(), first_pair.a), "A truncated generation recovers verified prior progress")
		_check(FileAccess.file_exists(archive) and FileAccess.get_file_as_string(archive) == damaged_bytes, "Damaged bytes are preserved in a separate immutable recovery artifact")
		_check(journey.accept_recording(first_pair.b), "Recovered interrupted write permits the next valid contribution")
		_check(FileAccess.get_file_as_string(archive) == damaged_bytes, "Later saves do not overwrite the preserved damaged artifact")


func _live_drafts() -> void:
	var path := _path("live")
	var journey := Journey.new(path)
	journey.load_data()
	var old := journey.create_live_simulation()
	var live := journey.create_live_simulation()
	_check(old != null and live != null, "Coordinator creates real context-bound simulation instances")
	old.step()
	live.step()
	_check(not journey.save_live_draft(old) and not journey.save_live_draft(RefCounted.new()) and not journey.save_live_draft(null), "Only the currently registered real engine may use live autosave")
	_check(journey.save_live_draft(live) and journey.role() == "a" and journey.pairs().is_empty(), "Live autosave durably preserves a rehearsal without advancing accepted progress")
	var expected: Dictionary = live.export_recording()
	_check(Canonical.same(journey.draft(), expected), "Accessing a live-saved draft for resume fully verifies it")
	var restarted := Journey.new(path)
	restarted.load_data()
	_check(not restarted.read_only and Canonical.same(restarted.draft(), expected), "Restart replays and verifies the exact live draft")
	_check(not restarted.save_live_draft(live), "A new coordinator does not inherit another instance's live-producer trust")
	_check(journey.save_draft({}) and not journey.save_live_draft(live), "Explicit retry invalidates the old live producer")
	_check(journey.accept_recording(first_pair.a), "Accept the earlier contribution for live source tests")
	for scenario: String in ["checkpoint", "prior", "definition", "stage", "role", "error"]:
		live = journey.create_live_simulation()
		live.step()
		var before := FileAccess.get_file_as_string(path)
		match scenario:
			"checkpoint": live.get("_checkpoint").players.p0.x += 1
			"prior": live.get("_prior").outcome.threw_seed = false
			"definition": live.level.seed_wait_ticks += 1
			"stage": live.stage.flight_ticks += 1
			"role": live.role = "a"
			"error": live.step({"unsupported": true})
		_check(not journey.save_live_draft(live) and FileAccess.get_file_as_string(path) == before, "Live " + scenario + " mutation cannot reuse unchanged hashes or overwrite saved evidence")
	live = journey.create_live_simulation()
	for frame: Dictionary in Simulation.expand_recording_inputs(first_pair.b):
		live.step(frame)
	_check(live.complete and journey.save_live_draft(live) and journey.role() == "b" and journey.pairs().is_empty(), "Even a completed live simulation stays a draft until an explicit accepted commit")
	_check(journey.accept_recording(live.export_recording()) and not journey.save_live_draft(live), "Explicit commit replay-verifies the live export and retires its old context")
	# A dishonest internal state cannot advance durable accepted progress: the
	# fast path is draft-only, and the next load must replay every action.
	live = journey.create_live_simulation()
	live.step()
	live.get("_players")[live.active_slot].x += 80
	_check(journey.save_live_draft(live), "Internal live producer exports are structurally saved as drafts only")
	var held_bytes := FileAccess.get_file_as_string(path)
	_check(not journey.accept_recording(live.export_recording()), "A structurally valid but unfaithful live export cannot commit")
	restarted = Journey.new(path)
	restarted.load_data()
	_check(restarted.read_only and restarted.draft().is_empty() and FileAccess.get_file_as_string(path) == held_bytes, "Restart detects a live draft whose state does not match its recorded actions and preserves bytes")
	var directory := _path("live-io").trim_suffix(".json")
	var missing := directory + "/chapter.json"
	paths.append(missing)
	var failing := Journey.new(missing)
	failing.load_data()
	var unfinished := failing.create_live_simulation()
	unfinished.step()
	_check(not failing.save_live_draft(unfinished) and failing.draft().is_empty() and failing.role() == "a" and not failing.last_error.is_empty(), "Failed live-draft I/O changes neither draft nor accepted role")


func _timings() -> void:
	# Each earlier recording and corresponding later recording lasts 590 ticks.
	# These are real simulated inputs, not enlarged dictionaries or skipped
	# validators. Report latency; do not turn an unknown device budget into a
	# fictional performance pass. Android frame-hitch measurement is separate.
	var initial := Catalog.initial_checkpoint(level)
	var long_a := _extended(initial, {}, "a", first_pair.a)
	var long_b := _extended(initial, long_a, "b", first_pair.b)
	var derived := Simulation.derive_checkpoint(level, initial, long_a, long_b)
	_check(derived.valid, "Timing stress uses a verified 590-tick first pair")
	if not derived.valid:
		return
	var garden_a := _extended(derived.checkpoint, {}, "a", second_pair.a)
	var garden_b := _extended(derived.checkpoint, garden_a, "b", second_pair.b)
	_check(int(long_a.duration_ticks) == 590 and int(long_b.duration_ticks) == 590 and int(garden_a.duration_ticks) == 590 and int(garden_b.duration_ticks) == 590, "All stress contributions are near the 600-tick limit")
	var path := _path("timing")
	var journey := Journey.new(path)
	journey.load_data()
	var accept_ms: Array[float] = []
	for recording: Dictionary in [long_a, long_b, garden_a]:
		var start := Time.get_ticks_usec()
		_check(journey.accept_recording(recording), "Accept real stress contribution")
		accept_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
	var draft_ms: Array[float] = []
	for iteration: int in range(5):
		var start := Time.get_ticks_usec()
		_check(journey.save_draft(garden_b), "Repeated warm stage2 draft still verifies and saves")
		draft_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
	var live := journey.create_live_simulation()
	_check(live != null, "Near-limit live timing uses the coordinator-owned real engine")
	var live_inputs := Simulation.expand_recording_inputs(garden_b)
	var live_ms: Array[float] = []
	var live_digests: Dictionary = {}
	for target: int in [540, 550, 560, 570, 580, 590]:
		while live.tick < target and not live.finished:
			live.step(live_inputs[live.tick])
		var live_start := Time.get_ticks_usec()
		_check(journey.save_live_draft(live), "Growing near-limit live draft saves without replaying its verified ancestors")
		live_ms.append(float(Time.get_ticks_usec() - live_start) / 1000.0)
		live_digests[live.export_recording().recording_hash] = true
	_check(live_digests.size() == 6, "Live timing covers six different growing recordings rather than cached identical dictionaries")
	var load_ms: Array[float] = []
	for iteration: int in range(3):
		var start := Time.get_ticks_usec()
		var reloaded := Journey.new(path)
		reloaded.load_data()
		load_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
		_check(not reloaded.read_only and reloaded.role() == "b" and reloaded.stage_id() == "garden", "Stress restart verifies full saved chain and draft")
	var start := Time.get_ticks_usec()
	_check(journey.accept_recording(garden_b), "Final stress commit verifies and completes")
	accept_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
	print("RELAY TIMING ms (desktop headless; 590 ticks/turn): " + JSON.stringify({"save_draft": _summary(draft_ms), "save_live_draft": _summary(live_ms), "load_data": _summary(load_ms), "accept_recording": _summary(accept_ms)}))


func _extended(checkpoint: Dictionary, prior: Dictionary, role: String, template: Dictionary) -> Dictionary:
	var sim := Simulation.new()
	_check(sim.reset(level, checkpoint.next_stage_id, checkpoint, prior, role), "Prepare near-limit timing simulation")
	for input: Dictionary in Simulation.expand_recording_inputs(template):
		sim.step(input)
	while sim.tick < 590 and not sim.finished:
		sim.step()
	return sim.export_recording()


func _summary(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {"samples": values, "p50": sorted[sorted.size() / 2], "max": sorted[-1]}


func _move(sim: RefCounted, destination: Vector2i) -> void:
	for axis: String in ["z", "x"]:
		for bound: int in range(200):
			var state: Dictionary = sim.snapshot()
			var current: int = state.players[state.active_slot][axis]
			var target := destination.x if axis == "x" else destination.y
			if current == target or sim.finished:
				break
			var change := clampf(float(target - current) / Simulation.MOVE_PER_TICK, -1.0, 1.0)
			sim.step({"move_" + axis: change})
		_check(sim.snapshot().players[sim.snapshot().active_slot][axis] == (destination.x if axis == "x" else destination.y), "Input fixture reaches authored waypoint axis " + axis)


func _wait_for_seed(sim: RefCounted) -> void:
	for bound: int in range(200):
		var state: Dictionary = sim.snapshot()
		if state.seed.status == "held" and state.seed.owner == state.active_slot:
			return
		sim.step()
	_check(false, "Input fixture catches the seed within its bounded rehearsal")


func _path(label: String) -> String:
	var path := "user://relay-test-" + label + "-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	paths.append(path)
	return path


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Write isolated save fixture")
	if file != null:
		file.store_string(text)
		file.close()


func _cleanup(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _finish() -> void:
	for path: String in paths:
		_cleanup(path)
	print("AFTER YOU RELAY JOURNEY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
