extends SceneTree
const PlayerCopy = preload("res://presentation/player_copy.gd")

const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var first: Dictionary = {}
var second: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_topology_and_controls()
	_test_complete_pair()
	_test_replay_and_tampering()
	_test_source_viability()
	_test_ghost_and_reset()
	_test_invalid_inputs()
	_check(checks >= 50 and not first.is_empty() and not second.is_empty(), "All first-stage test groups reached their assertions")
	print("AFTER YOU BORROWED LIGHT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_topology_and_controls() -> void:
	var sim := Simulation.new()
	_check(sim.reset(), "Borrowed Light starts from its authored state")
	_check(sim.walkable_at(-700, 0) and sim.walkable_at(0, 0), "Both separate islands are walkable")
	_check(not sim.walkable_at(-350, 0) and not sim.walkable_at(-450, 100), "The bridge gap and route around its edge are physically closed")
	_check(not sim.snapshot().emitter_powered and sim.snapshot().optics.segments.is_empty(), "The source is initially dark without its owner's pad hold")
	for _i in range(70):
		sim.step({"move_x": 1})
	_check(sim.snapshot().players.p0.x <= -462 and not sim.snapshot().crossed_bridge, "Actual movement cannot tunnel across the dark gap")
	_check(not sim.can_commit(), "Reaching the closed gap cannot substitute for holding the emitter")
	var control := Simulation.new()
	control.reset()
	_move(control, "p0", [-560, -100])
	control.step({"interact": true})
	_check(control.snapshot().mirror_orientation == "backslash" and not control.snapshot().context_action.enabled, "A cannot rotate the partner's mirror even while beside it")
	_check(not control.complete, "Pressing the action away from the Court cannot fabricate its objective")

func _test_complete_pair() -> void:
	var a := _first(140)
	first = a.export_recording()
	_check(a.can_commit() and not a.complete, "A may finish a steady light contribution without claiming stage completion")
	_check(a.snapshot().emitter_powered and not a.snapshot().bridges["harbour-court"], "Holding the source lights the wrong-facing mirror but does not directly open the bridge")
	_check(a.snapshot().optics.segments.size() == 2 and not a.snapshot().optics.signals["harbour-receiver"], "The beam visibly leaves the initial mirror in the wrong direction")
	_check(Simulation.verify_recording(first).valid, "The full first contribution verifies from real recorded controls")
	var original := Canonical.digest(first)
	var b := Simulation.new()
	_check(b.reset("b", first), "B starts with the verified source contribution")
	b.step({"interact": true})
	_check(not b.snapshot().objective_done and b.snapshot().mirror_orientation == "backslash", "Pressing Action at the spawn neither rotates a distant mirror nor rings the bell")
	b.step({})
	_to_mirror(b)
	_check(b.snapshot().context_action.id == "rotate" and b.snapshot().context_action.enabled, "The mirror interaction becomes available only beside the mirror")
	b.step({"interact": true})
	_check(b.snapshot().optics.signals["harbour-receiver"] and b.snapshot().bridges["harbour-court"], "A real mirror rotation routes A's light into the receiver and opens the bridge")
	_check(b.walkable_at(-350, 0) and not b.walkable_at(-350, 45), "The activated bridge permits its centre route but rejects footprint overhang")
	for _i in range(5):
		b.step({"interact": true})
	_check(b.snapshot().mirror_orientation == "slash", "Holding the interaction button rotates only once")
	b.step({})
	b.step({"interact": true})
	_check(not b.snapshot().bridges["harbour-court"] and not b.snapshot().optics.signals["harbour-receiver"], "A second distinct press turns the receiver and gate off")
	b.step({})
	b.step({"interact": true})
	b.step({})
	_to_bell(b)
	_check(b.snapshot().crossed_bridge and b.snapshot().players.p1.surface_id == "court", "The route physically crosses the receiver-gated gap into Court")
	_check(not b.complete and not b.snapshot().objective_done, "Crossing alone does not invent the bell interaction")
	b.step({"interact": true})
	_check(b.snapshot().objective_done and not b.complete and b.tick < a.tick, "Ringing the bell early preserves its result while waiting for the complete source recording")
	while not b.finished:
		b.step({})
	second = b.export_recording()
	_check(b.complete and b.can_commit() and b.tick == a.tick, "The stage finishes only after the full earlier contribution has played")
	_check(Canonical.same(_bare_player(b.snapshot().players.p0), _bare_player(a.snapshot().players.p0)), "The final ghost endpoint is the exact source endpoint")
	_check(Canonical.digest(first) == original, "B's rotations, crossing and acceptance never mutate A's recording")
	var derived := Simulation.derive_stage_result(first, second)
	_check(derived.valid and derived.result.mechanisms.emitter_latched and derived.result.mechanisms.bridge_latched, "Only a verified completed pair derives the Court's remembered light and route")
	_check(Canonical.same(derived.result.players.p1, _bare_player(b.snapshot().players.p1)), "The derived result preserves the actual later-player endpoint without teleporting")
	var before := b.state_hash()
	b.step({"move_x": -1, "interact": true})
	_check(b.state_hash() == before, "Inputs after completion cannot mutate the finished turn")

func _test_replay_and_tampering() -> void:
	var first_json: Dictionary = JSON.parse_string(JSON.stringify(first))
	var second_json: Dictionary = JSON.parse_string(JSON.stringify(second))
	_check(Simulation.verify_recording(first_json).valid and Simulation.verify_recording(second_json, first_json).valid, "Actual JSON reload retains deterministic source and combined replay")
	var check := Simulation.verify_recording(second, first)
	_check(check.valid and check.snapshot.complete, "B's full replay reproduces the completed optical crossing")
	var replay := Simulation.new()
	replay.reset("b", first)
	var inputs := Simulation.expand_recording_inputs(second)
	for index in range(inputs.size()):
		replay.step(inputs[index])
		# Presentation may read repeatedly between any pair of fixed ticks.
		for _sample in range((index % 4) + 1):
			replay.snapshot()
	_check(Canonical.same(replay.export_recording(), second), "Different numbers of render observations do not affect recording or outcome")
	var incomplete := Simulation.new()
	incomplete.reset("b", first)
	incomplete.step({})
	_check(Simulation.verify_recording(incomplete.export_recording(), first).valid and not incomplete.can_commit(), "A truthful unfinished draft is replay-valid but cannot be committed")
	_check(not Simulation.derive_stage_result(first, incomplete.export_recording()).valid, "An unfinished draft cannot produce a completed-stage result")
	var altered := second.duplicate(true)
	altered.completed = false
	_rehash(altered)
	_check(not Simulation.verify_recording(altered, first).valid, "Rehashing an invented outcome does not bypass deterministic verification")
	altered = second.duplicate(true)
	altered.actions[0].x = 1
	_rehash(altered)
	_check(not Simulation.verify_recording(altered, first).valid, "Rehashed altered actions fail against the actual replay state")
	altered = second.duplicate(true)
	altered.replay_checks[0].state_hash = "a".repeat(64)
	_rehash(altered)
	_check(not Simulation.verify_recording(altered, first).valid, "Rehashed tampered intermediate integrity checks are rejected")
	var replacement: Dictionary = _first(141).export_recording()
	_check(not Simulation.verify_recording(second, replacement).valid, "Even an equivalent steady light with a different duration is a different immutable dependency")
	altered = second.duplicate(true)
	altered.source_recording_hash = replacement.recording_hash
	_rehash(altered)
	_check(not Simulation.verify_recording(altered, replacement).valid, "Changing and rehashing the dependency does not silently reinterpret B")
	altered = first.duplicate(true)
	altered.simulation_version = 2
	_rehash(altered)
	_check(not Simulation.verify_recording(altered).valid, "Relay simulation version 2 cannot be interpreted as Lighthouse version 3")
	altered = first.duplicate(true)
	altered.definition_hash = "b".repeat(64)
	_rehash(altered)
	_check(not Simulation.verify_recording(altered).valid, "Another level definition cannot reuse this stage's controls")
	altered = first.duplicate(true)
	altered.actions[0].ticks = 601
	_rehash(altered)
	_check(not Simulation.verify_recording(altered).valid and Simulation.expand_recording_inputs(altered).is_empty(), "Oversized action runs fail before expansion")
	altered = first.duplicate(true)
	altered.checkpoint = {"completed": true}
	_check(not Simulation.verify_recording(altered).valid, "A supplied checkpoint cannot inject state into the fixed-start stage")

func _test_source_viability() -> void:
	var idle := Simulation.new()
	idle.reset()
	for _i in range(30):
		idle.step({"interact": true})
	_check(not idle.can_commit() and not Simulation.new().reset("b", idle.export_recording()), "An idle or repeated-button source cannot start B")
	var brief := Simulation.new()
	brief.reset()
	for _i in range(4):
		brief.step({"move_x": 1})
	_check(brief.snapshot().emitter_powered and not brief.can_commit(), "A one-tick flash of light is not a viable source")
	var broken := _first(25)
	for _i in range(10):
		broken.step({"move_x": -1})
	for _i in range(10):
		broken.step({"move_x": 1})
	_check(broken.snapshot().emitter_powered and not broken.can_commit() and "released" in broken.commit_reason(), "Leaving and returning cannot erase a broken source hold")
	_check(not Simulation.new().reset("b", broken.export_recording()), "B rejects an apparently lit endpoint with an interrupted earlier hold")
	var latest := Simulation.MAX_TICKS - Simulation.receiver_budget_ticks()
	var border := _first(latest + 14, latest - 4)
	_check(border.snapshot().first_power_tick == latest and border.can_commit(), "The conservative latest viable source activation is accepted at its exact boundary")
	var b := Simulation.new()
	b.reset("b", border.export_recording())
	for _i in range(latest):
		b.step({})
	_to_mirror(b)
	b.step({"interact": true})
	b.step({})
	_to_bell(b)
	b.step({"interact": true})
	_check(b.complete and b.tick <= Simulation.MAX_TICKS, "The authored receiver control route actually succeeds after the borderline source activation")
	var late := _first(latest + 15, latest - 3)
	_check(not late.can_commit() and late.commit_reason() == PlayerCopy.BORROWED_LIGHT_846C2C892A05, "One tick beyond the conservative source budget is held with an actionable reason")
	_check(not Simulation.new().reset("b", late.export_recording()), "B cannot accept an over-late source even after it held the pad")

func _test_ghost_and_reset() -> void:
	var source_copy := first.duplicate(true)
	var b := Simulation.new()
	b.reset("b", source_copy)
	source_copy.actions[0].x = -1
	# Two opposing diagonal steps change Z by 12 without changing X, aligning
	# B's real control grid with A's pad position before the overlap check.
	b.step({"move_x": 1, "move_z": -1})
	b.step({"move_x": -1, "move_z": -1})
	_move(b, "p1", [-728, 68])
	_move(b, "p1", [-728, -100])
	_check(b.snapshot().emitter_powered and b.snapshot().players.p0.x == -728 and b.snapshot().players.p0.z == -100, "A later player may pass through the ghost on its pad without pushing it or extinguishing its light")
	_check(b.snapshot().players.p1.x == b.snapshot().players.p0.x and b.snapshot().players.p1.z == b.snapshot().players.p0.z, "The ghost is actually nonblocking rather than being avoided by the route")
	b.step({"interact": true})
	_check(b.snapshot().emitter_powered and b.snapshot().mirror_orientation == "backslash", "B's action on the source pad cannot change a source-owned emitter")
	var held := b.state_hash()
	for _i in range(20):
		b.snapshot()
	_check(b.state_hash() == held, "Pausing without ticks preserves source playback and the draft")
	var exposed := b.snapshot()
	exposed.players.p0.x = 0
	exposed.optics.signals["harbour-receiver"] = true
	_check(b.state_hash() == held and not b.snapshot().bridges["harbour-court"], "Presentation snapshots cannot alter internal actors or optical gates")
	_check(not b.reset("unknown") and not b.snapshot().can_commit, "A failed reset cannot continue a previously valid loaded turn")
	b.step({"move_x": 1})
	_check(b.export_recording().is_empty(), "Stepping after setup failure cannot export stale prior gameplay")
	_check(b.reset() and b.tick == 0 and not b.snapshot().emitter_powered and not b.snapshot().crossed_bridge, "A new rehearsal clears previous source, optical and crossing state")

func _test_invalid_inputs() -> void:
	for input: Dictionary in [{"move_x": INF}, {"move_z": 1.1}, {"move_x": true}, {"interact": "yes"}, {"complete": true}]:
		var sim := Simulation.new()
		sim.reset()
		sim.step(input)
		_check(not sim.error.is_empty() and sim.tick == 0 and sim.export_recording().is_empty(), "Malformed controls cannot advance or fabricate a recorded state")
	_check(not Simulation.new().reset("a", first), "First contributions reject unexpected source dependencies")
	_check(not Simulation.verify_recording({}, first).valid, "Missing recording data fails closed")
	var fractional := Simulation.new()
	fractional.reset()
	fractional.step({"move_x": 0.2})
	_check(fractional.snapshot().players.p0.x == -760, "Small joystick noise stays inside the dead zone")
	fractional.step({"move_x": 0.7})
	_check(fractional.snapshot().players.p0.x == -752 and Simulation.verify_recording(fractional.export_recording()).valid, "Supported analog input records its exact discrete movement")

func _first(total_ticks: int, delay: int = 0) -> RefCounted:
	var sim := Simulation.new()
	sim.reset()
	for _i in range(delay):
		sim.step({})
	for _i in range(4):
		sim.step({"move_x": 1})
	while sim.tick < total_ticks and not sim.finished:
		sim.step({})
	return sim

func _to_mirror(sim: RefCounted) -> void:
	_move(sim, "p1", [-560, 80])
	_move(sim, "p1", [-560, -96])

func _to_bell(sim: RefCounted) -> void:
	_move(sim, "p1", [-560, 0])
	_move(sim, "p1", [-160, 0])

func _move(sim: RefCounted, slot: String, destination: Array) -> void:
	for _i in range(200):
		var player: Dictionary = sim.snapshot().players[slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		if absi(dx) <= 3 and absi(dz) <= 3:
			return
		if sim.finished:
			return
		sim.step({"move_x": signi(dx) if absi(dx) > 3 else 0, "move_z": 0 if absi(dx) > 3 else signi(dz)})

func _bare_player(player: Dictionary) -> Dictionary:
	return {"x": player.x, "z": player.z, "surface_id": player.surface_id}

func _rehash(record: Dictionary) -> void:
	record.recording_hash = Simulation.recording_hash(record)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
