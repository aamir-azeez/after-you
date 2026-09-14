extends SceneTree

const Simulation = preload("res://core/v2/simulation_v2.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var definition: Dictionary = Catalog.relay_isles()
var initial: Dictionary = Catalog.initial_checkpoint(definition)
var first_a: Dictionary
var first_b: Dictionary
var relay_checkpoint: Dictionary
var second_a: Dictionary
var second_b: Dictionary
var final_checkpoint: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_topology()
	_test_first_stage()
	if not relay_checkpoint.is_empty():
		_test_second_stage()
		_test_dependencies_and_checkpoints()
	_test_recording_rejections()
	_test_ghost_and_retry()
	_test_invalid_controls_and_versions()
	_test_source_viability()
	_check(checks >= 60 and not final_checkpoint.is_empty(), "The full two-stage test run reached its completion assertions")
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
		_write_fixtures()
	print("AFTER YOU SIMULATION V2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_topology() -> void:
	var sim := Simulation.new()
	_check(sim.reset(definition, "relay", initial), "Canonical v2 first-stage setup succeeds")
	_check(sim.walkable_at(-400, 0) and sim.walkable_at(40, 0) and sim.walkable_at(420, 0), "All three islands exist as actual distinct walkable surfaces")
	_check(not sim.walkable_at(-200, 0) and not sim.walkable_at(280, 0), "Both separate gaps are initially blocked")
	_check(not sim.walkable_at(-260, 190) and not sim.walkable_at(220, 190), "An island edge cannot be crossed around either bridge")
	_walk(sim, [-400, 0])
	sim.step({})
	_check(sim.snapshot().bridges["west-relay"] and not sim.snapshot().bridges["relay-east"], "First controller only opens its own bridge")
	_check(sim.walkable_at(-200, 0) and not sim.walkable_at(280, 0), "Open bridge geometry connects exactly one gap")
	_check(sim.walkable_at(-260, 0) and sim.walkable_at(-140, 0), "Player-radius checks permit continuous seam traversal between island and bridge")
	_check(not sim.walkable_at(-200, 60), "Player radius cannot overhang the narrow bridge edge")
	var blocked := Simulation.new()
	blocked.reset(definition, "relay", initial)
	for _i in range(80):
		blocked.step({"move_x": 1.0})
	_check(int(blocked.snapshot().players.p0.x) <= -272, "Real movement cannot tunnel across the closed first gap")

func _test_first_stage() -> void:
	var a := _solve_first(initial, "relay")
	first_a = a.export_recording()
	_check(a.can_commit() and a.tick < Simulation.MAX_TICKS, "A may Finish a viable throw without filling twenty seconds")
	_check(not a.complete and a.snapshot().outcome.threw_seed, "A's contribution is not itself a completed stage")
	var before := Canonical.digest(first_a)
	var b := _start_second(initial, first_a)
	_walk(b, [-320, 0])
	while not b.snapshot().bridges["west-relay"] and not b.finished:
		b.step({})
	_walk(b, [-10, 0])
	while b.snapshot().seed.status != "held" and not b.finished:
		b.step({})
	_walk(b, [40, 0])
	b.step({"interact": true})
	_check(b.snapshot().outcome.placed_relay and not b.complete and b.tick < a.tick, "Placing the seed before A ends waits for the remaining source contribution")
	while not b.finished:
		b.step({})
	first_b = b.export_recording()
	_check(b.complete and b.can_commit() and b.tick == a.tick, "Stage completes after the full earlier contribution is consumed")
	_check(b.snapshot().seed.status == "socket" and b.snapshot().seed.socket_id == "relay-socket", "The first goal deposits a persistent relay seed instead of planting the final garden")
	_check(b.snapshot().bridges["west-relay"] and not b.snapshot().bridges["relay-east"], "Relay completion preserves first crossing while the second stays closed")
	_check(Canonical.digest(first_a) == before, "Later replay never rewrites the earlier committed recording")
	var derived := Simulation.derive_checkpoint(definition, initial, first_a, first_b)
	_check(derived.valid, "A verified complete pair derives a gameplay checkpoint")
	if not derived.valid:
		return
	relay_checkpoint = derived.checkpoint
	_check(relay_checkpoint.stage_index == 1 and relay_checkpoint.next_stage_id == "garden", "Checkpoint advances one stage, not the entire chapter")
	_check(relay_checkpoint.players.p0.x == b.snapshot().players.p0.x and relay_checkpoint.players.p0.z == b.snapshot().players.p0.z and relay_checkpoint.players.p1.x == b.snapshot().players.p1.x and relay_checkpoint.players.p1.z == b.snapshot().players.p1.z, "Checkpoint stores both exact physical endpoints without teleporting or exchanging slots")
	_check(relay_checkpoint.latched_bridges == ["west-relay"] and relay_checkpoint.seed.status == "socket", "The solved route and relay socket survive the stage boundary")
	_check(Simulation.verify_checkpoint(definition, _json(relay_checkpoint)).valid, "Checkpoint survives actual JSON reload and source-chain replay")
	_check(Simulation.verify_recording(definition, _json(first_a), initial).valid and Simulation.verify_recording(definition, _json(first_b), initial, _json(first_a)).valid, "Both stage-one records verify after JSON integer/float conversion")

func _test_second_stage() -> void:
	var a := Simulation.new()
	_check(a.reset(definition, "garden", relay_checkpoint), "Next stage starts from the verified relay checkpoint")
	var state := a.snapshot()
	_check(a.active_slot == "p1" and a.first_player_slot == "p1", "The former receiver is now the earlier contributor")
	_check(state.players.p0.x == relay_checkpoint.players.p0.x and state.players.p1.x == relay_checkpoint.players.p1.x, "Role reversal retains physical player positions")
	_check(a.context_action().id == "take" and a.context_action().enabled, "Relay socket offers a real Take seed action to its next owner")
	a.step({"interact": true})
	_check(a.snapshot().seed.owner == "p1" and a.snapshot().outcome.took_seed, "Taking the seed changes explicit prop ownership")
	a.step({"interact": true})
	_check(not a.snapshot().outcome.threw_seed, "Holding the same action cannot take and throw twice")
	_walk(a, [100, 0])
	a.step({})
	a.step({"interact": true})
	while a.tick < 150:
		a.step({})
	second_a = a.export_recording()
	_check(a.can_commit() and a.snapshot().bridges["west-relay"] and a.snapshot().bridges["relay-east"], "Second plate opens the new crossing without losing the latched first bridge")
	var b := _start_second(relay_checkpoint, second_a)
	_walk(b, [420, 0])
	while b.snapshot().seed.status != "held" and not b.finished:
		b.step({})
	_walk(b, [620, 120])
	b.step({"interact": true})
	while not b.finished:
		b.step({})
	second_b = b.export_recording()
	_check(b.complete and b.tick < 600 and b.active_slot == "p0", "Original first player crosses both gaps and completes the final garden through normal controls")
	_check(b.snapshot().seed.status == "planted" and b.snapshot().outcome.planted_seed, "Second stage has a distinct final planting outcome")
	var derived := Simulation.derive_checkpoint(definition, relay_checkpoint, second_a, second_b)
	_check(derived.valid, "Second actual A/B pair derives its final verified checkpoint")
	if derived.valid:
		final_checkpoint = derived.checkpoint
		_check(final_checkpoint.stage_index == 2 and final_checkpoint.next_stage_id.is_empty(), "Final checkpoint ends the chapter without inventing later stages")
		_check(Simulation.verify_checkpoint(definition, _json(final_checkpoint)).valid, "Complete two-stage checkpoint chain verifies after reload")
	for pair: Array in [[initial, first_a, first_b], [relay_checkpoint, second_a, second_b]]:
		for rate in [30, 60, 120]:
			var replay := _start_second(pair[0], pair[1])
			for input: Dictionary in Simulation.expand_recording_inputs(pair[2]):
				replay.step(input)
				for _frame in range(rate / 30):
					var ignored := replay.snapshot()
					ignored.players.p0.x = 99999
			_check(replay.complete and replay.state_hash() == pair[2].final_state_hash, "Read-only presentation at %d fps preserves stage %s replay" % [rate, pair[2].stage_id])

func _test_dependencies_and_checkpoints() -> void:
	var alternate := Simulation.new()
	alternate.reset(definition, "relay", initial)
	var inputs := Simulation.expand_recording_inputs(first_a)
	inputs[50] = {"move_x": 1.0}
	inputs[51] = {"move_x": -1.0}
	for input: Dictionary in inputs:
		alternate.step(input)
	var changed := alternate.export_recording()
	_check(alternate.can_commit() and changed.final_state_hash == first_a.final_state_hash, "Alternative viable inputs can deliberately reach the same final state")
	_check(changed.recording_hash != first_a.recording_hash, "V2 full content hash distinguishes same-state different input recordings")
	_check(not Simulation.verify_recording(definition, first_b, initial, changed).valid, "B cannot silently substitute a different same-state source recording")
	var edit := _json(relay_checkpoint)
	edit.players.p0.x = -500
	edit.checkpoint_hash = Catalog.checkpoint_hash(edit)
	_check(not Simulation.verify_checkpoint(definition, edit).valid, "Rehashing invented checkpoint coordinates does not bypass source-pair replay")
	edit = _json(relay_checkpoint)
	edit.seed.owner = "p0"
	edit.checkpoint_hash = Catalog.checkpoint_hash(edit)
	_check(not Simulation.verify_checkpoint(definition, edit).valid, "Rehashing forged prop ownership does not bypass derived checkpoint validation")
	edit = _json(relay_checkpoint)
	edit.proof.a = changed
	_check(not Simulation.verify_checkpoint(definition, edit).valid, "Changing a checkpoint's earlier source invalidates its dependent pair")
	var sim := Simulation.new()
	_check(not sim.reset(definition, "garden", initial), "A stale stage-zero checkpoint cannot start the next stage")
	_check(not sim.reset(definition, "relay", relay_checkpoint), "A later checkpoint cannot reinterpret an earlier stage")
	_check(not sim.reset(definition, "garden", relay_checkpoint, first_a, "b"), "An earlier-stage A cannot supply a new-stage B")
	_check(not Simulation.derive_checkpoint(definition, initial, first_b, first_a).valid, "Checkpoint derivation rejects a reversed A/B pair")

func _test_recording_rejections() -> void:
	if first_a.is_empty():
		return
	var edit := _json(first_a)
	edit.actions[0].teleport = true
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial).valid, "Unknown action keys are rejected even with a new content hash")
	edit = _json(first_a)
	edit.outcome.planted_seed = true
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial).valid, "Rehashed fabricated outcome is rejected by actual replay")
	edit = _json(first_a)
	edit.replay_checks.pop_front()
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial).valid, "Dropping an intermediate replay check is not silently accepted")
	edit = _json(first_a)
	edit.player_slot = "p1"
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial).valid, "Recordings cannot substitute the other physical player")
	edit = _json(first_a)
	edit.actions[0].ticks = 601
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial).valid, "Oversized action runs are rejected before replay expansion")
	edit = _json(first_b)
	edit.actions.append({"ticks": 1, "x": 0, "z": 0, "action": false})
	edit.duration_ticks += 1
	edit.replay_checks[-1].tick += 1
	edit.recording_hash = Simulation.recording_hash(edit)
	_check(not Simulation.verify_recording(definition, edit, initial, first_a).valid, "A record cannot append inputs after a completed stage")
	edit = _json(initial)
	edit.latched_bridges = ["west-relay", "relay-east"]
	edit.checkpoint_hash = Catalog.checkpoint_hash(edit)
	_check(not Simulation.verify_checkpoint(definition, edit).valid, "Initial checkpoint cannot grant solved bridges by self-hashing")
	edit = _json(initial)
	edit.stage_index = 3
	_check(not Simulation.verify_checkpoint(definition, edit).valid, "Checkpoint chains are bounded to the authored chapter")

func _test_ghost_and_retry() -> void:
	if first_a.is_empty():
		return
	var b := _start_second(initial, first_a)
	_walk(b, [-400, -120])
	_walk(b, [-400, 0])
	_check(b.snapshot().players.p0.x == b.snapshot().players.p1.x and b.snapshot().players.p0.z == b.snapshot().players.p1.z, "Receiver can overlap the ghost without blocking or pushing it")
	b.step({"interact": true})
	_check(b.snapshot().seed.owner != "p1", "Interacting beside a reserved seed does not steal it before handoff")
	var old_hash := Canonical.digest(first_a)
	while not b.finished:
		b.step({})
	_check(not b.complete and not b.can_commit() and b.snapshot().seed.status == "missed", "Missed catch creates a retryable uncompleted stage")
	var missed := b.export_recording()
	_check(Simulation.verify_recording(definition, missed, initial, first_a).valid, "An incomplete draft remains truthfully replayable without becoming committable")
	_check(not Simulation.derive_checkpoint(definition, initial, first_a, missed).valid, "Incomplete catch attempt cannot create a checkpoint")
	_check(Canonical.digest(first_a) == old_hash and b.reset(definition, "relay", initial, first_a, "b"), "Retry preserves and reuses the exact accepted earlier contribution")
	var a := Simulation.new()
	a.reset(definition, "relay", initial)
	for _i in range(12):
		a.step({"move_x": 1.0})
	var draft := a.export_recording()
	var paused := a.state_hash()
	for _i in range(10):
		a.snapshot()
	_check(a.state_hash() == paused and a.tick == 12, "Reading a paused/background draft never advances fixed simulation time")
	var check := Simulation.verify_recording(definition, draft, initial)
	_check(check.valid and not check.snapshot.can_commit, "Partial saved contribution verifies without relaxing the commit requirements")

func _test_invalid_controls_and_versions() -> void:
	for input: Dictionary in [{"teleport": true}, {"move_x": NAN}, {"move_z": 1.1}, {"interact": "yes"}]:
		var sim := Simulation.new()
		sim.reset(definition, "relay", initial)
		sim.step(input)
		_check(not sim.error.is_empty() and sim.tick == 0 and sim.export_recording().is_empty(), "Unsupported control input holds without recording fabricated actions")
	var sim := Simulation.new()
	var unknown := definition.duplicate(true)
	unknown.version = 3
	_check(not sim.reset(unknown, "relay", initial), "Unsupported future definition version is held")
	_check(not sim.reset(definition, "missing", initial) and not sim.reset(definition, "relay", initial, {}, "guest"), "Unknown stage and role are held")
	unknown = definition.duplicate(true)
	unknown.bridges[0].rect_cm[0] -= 50
	_check(not sim.reset(unknown, "relay", initial), "Changing authored geometry requires a new supported definition")

func _test_source_viability() -> void:
	# Relay arc 90 + seven walking ticks + landing/action ticks = 99 ticks.
	# The earliest catch is deliberately not used to relax this bound.
	var edge := Simulation.new()
	edge.reset(definition, "relay", initial)
	_walk(edge, [-400, 0])
	while edge.tick < 501:
		edge.step({})
	edge.step({"interact": true})
	_check(edge.can_commit(), "Last conservative relay throw boundary remains committable")
	var source := edge.export_recording()
	var receiver := _start_second(initial, source)
	receiver.catch_assistance = false
	_walk(receiver, [-320, 0])
	while not receiver.snapshot().bridges["west-relay"] and not receiver.finished:
		receiver.step({})
	_walk(receiver, [-10, 0])
	while not receiver.context_action().enabled and not receiver.finished:
		receiver.step({})
	receiver.step({"interact": true})
	_walk(receiver, [40, 0])
	receiver.step({"interact": true})
	_check(receiver.complete and receiver.tick <= 600 and receiver.snapshot().outcome.caught_seed, "Boundary source has an actual manual-catch and delivery witness within the turn budget")
	for late_tick in [502, 599]:
		var late := Simulation.new()
		late.reset(definition, "relay", initial)
		_walk(late, [-400, 0])
		while late.tick < late_tick:
			late.step({})
		_check(not late.context_action().enabled, "Late throw control is disabled at tick %d" % late_tick)
		late.step({"interact": true})
		_check(not late.can_commit() and not late.snapshot().outcome.threw_seed and "earlier" in late.snapshot().message, "Late tick %d action cannot create an impossible accepted A and explains retry" % late_tick)
		_check(not Simulation.new().reset(definition, "relay", initial, late.export_recording(), "b"), "Receiver rejects the incomplete late-source contribution")
	# Garden's longer landing-to-goal route has its own derived bound:
	# 120 arc + 25 x-walk + 15 z-walk + two transition/action ticks = 162.
	if not relay_checkpoint.is_empty():
		var garden := Simulation.new()
		garden.reset(definition, "garden", relay_checkpoint)
		garden.step({"interact": true})
		_walk(garden, [100, 0])
		while garden.tick < 438:
			garden.step({})
		_check(garden.context_action().enabled, "Garden budget permits its last safe 438-tick throw boundary")
		garden.step({})
		_check(not garden.context_action().enabled, "Garden budget accounts for its longer delivery route instead of reusing relay timing")
	var interrupted := Simulation.new()
	interrupted.reset(definition, "relay", initial)
	_walk(interrupted, [-400, 0])
	interrupted.step({"interact": true})
	for _index in range(6):
		interrupted.step({"move_z": 1.0})
	_check(not interrupted.snapshot().bridges["west-relay"], "Leaving the held plate actually closes the source bridge")
	for _index in range(6):
		interrupted.step({"move_z": -1.0})
	_check(interrupted.snapshot().bridges["west-relay"] and not interrupted.can_commit(), "Returning later cannot erase a post-throw bridge interruption")
	_check("released" in interrupted.commit_reason(), "Interrupted-source refusal explains the explicit hold-plate requirement")
	var recorded := interrupted.export_recording()
	var check := Simulation.verify_recording(definition, recorded, initial)
	_check(check.valid and not check.snapshot.can_commit, "Source interruption survives deterministic replay as an uncommittable draft")
	_check(not Simulation.new().reset(definition, "relay", initial, recorded, "b"), "Receiver refuses an interrupted A instead of becoming trapped by an unusable accepted source")

func _solve_first(checkpoint: Dictionary, stage_id: String) -> AfterYouSimulationV2:
	var sim := Simulation.new()
	_check(sim.reset(definition, stage_id, checkpoint), "Source contribution initializes from its exact checkpoint")
	if stage_id == "garden":
		sim.step({"interact": true})
	_walk(sim, [-400, 0] if stage_id == "relay" else [100, 0])
	sim.step({})
	sim.step({"interact": true})
	while sim.tick < (140 if stage_id == "relay" else 150):
		sim.step({})
	return sim

func _start_second(checkpoint: Dictionary, first: Dictionary) -> AfterYouSimulationV2:
	var sim := Simulation.new()
	_check(sim.reset(definition, first.stage_id, checkpoint, first, "b"), "Receiver initializes with a viable exact source recording")
	return sim

func _walk(sim: AfterYouSimulationV2, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		while not sim.finished and sim.error.is_empty():
			var state: Dictionary = sim.snapshot().players[sim.active_slot]
			var distance := int(target[index]) - int(state[axis])
			if absi(distance) <= 1:
				break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / Simulation.MOVE_PER_TICK, -1.0, 1.0)
			sim.step(input)
	_check(not sim.finished or sim.complete, "Control route reaches its waypoint before timeout")

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _write_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures/v2")
	var items := {"relay-a": first_a, "relay-b": first_b, "garden-a": second_a, "garden-b": second_b, "initial-checkpoint": initial, "relay-checkpoint": relay_checkpoint, "final-checkpoint": final_checkpoint}
	for name: String in items:
		var file := FileAccess.open("res://tests/fixtures/v2/" + name + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(Canonical.normalized(items[name]), "\t") + "\n")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
