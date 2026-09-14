extends SceneTree

const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Catalog = preload("res://core/lighthouse/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var pairs: Array = []
var checkpoints: Array = []
var first: Dictionary = {}
var second: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
	if not fixture is Dictionary or not fixture.get("pairs") is Array or fixture.pairs.size() != 2 or not fixture.get("checkpoints") is Array or fixture.checkpoints.size() != 3:
		_check(false, "The frozen first-two-stage fixture is present and complete")
		_finish()
		return
	pairs = fixture.pairs
	checkpoints = fixture.checkpoints
	_test_previous_formats()
	_test_persistent_start()
	_test_distinct_roles_and_paths()
	_test_simultaneous_signals()
	_test_resume_and_checkpoint()
	_test_source_deadline()
	_test_negative_evidence()
	_test_north_endpoint()
	_check(checks >= 45 and not second.is_empty(), "All stage-three groups reached their independent objective assertions")
	_finish()

func _finish() -> void:
	print("AFTER YOU TWO PROMISES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_previous_formats() -> void:
	var prefix: Array = []
	_check(Canonical.same(Simulation.initial_checkpoint(), checkpoints[0]), "The original initial checkpoint remains byte-equivalent")
	for index in range(2):
		var pair: Dictionary = pairs[index]
		for role: String in ["a", "b"]:
			var source: Dictionary = pair.a if role == "b" else {}
			var checked := Simulation.verify_recording(pair[role], source, prefix)
			_check(checked.valid, "Frozen earlier recording still replay-verifies at its exact stage and source")
			var replay := Simulation.new()
			replay.reset(role, source, prefix)
			for input: Dictionary in Simulation.expand_recording_inputs(pair[role]):
				replay.step(input)
			_check(Canonical.same(replay.export_recording(), pair[role]), "The extended engine preserves every frozen action/checkpoint/final recording hash")
		prefix.append(pair)
		var derived := Simulation.checkpoint_from_pairs(prefix)
		_check(derived.valid and Canonical.same(derived.checkpoint, checkpoints[index + 1]), "Adding a stage does not reinterpret the prior derived checkpoint")

func _test_persistent_start() -> void:
	var sim := Simulation.new()
	_check(sim.reset("a", {}, pairs) and sim.snapshot().stage_id == "two-promises", "The third stage starts from the two complete verified pairs")
	var state := sim.snapshot()
	_check(state.active_slot == "p0" and state.first_player_slot == "p0", "The next first-player role alternates back to physical p0")
	_check(Canonical.same(_bare(state.players.p0), checkpoints[2].players.p0) and Canonical.same(_bare(state.players.p1), checkpoints[2].players.p1), "Both actual second-stage endpoints survive without teleportation")
	_check(Canonical.same(state.props["portable-lens"], checkpoints[2].mechanisms.props["portable-lens"]), "The exact fitted lens state is carried forward, not spawned again")
	_check(state.props["portable-lens"].status == "fitted" and state.props["portable-lens"].holder_slot == "", "The installed lens remains in its socket without another carrier")
	_check(state.bridges["harbour-court"] and state.bridges["court-north"] and state.bridges["court-south"], "Remembered bridges remain safe and the installed lens powers the distinct South route")
	_check(not sim.walkable_at(40,180) and sim.walkable_at(-48,180) and sim.walkable_at(56,350), "South is a real island reached through its actual narrow bridge, not a decorative extension")
	_check(state.optics.segments.size() == 4 and not state.optics.signals["north-promise"] and not state.optics.signals["south-promise"], "The installed lens powers two initially misaligned optical paths")
	_check(not state.receiver_goal.unlocked and not state.objective_done and not sim.can_commit(), "An inherited lens and two bridges alone do not complete the new puzzle")
	_move(sim, [40,116])
	for _i in range(35):
		sim.step({"move_z":1})
	_check(sim.snapshot().players.p0.surface_id == "court" and sim.snapshot().players.p0.z <= 118, "Actual controls cannot step around the new bridge across empty space")
	_check(Catalog.definition("a-welcome-left-on").is_empty(), "The sixth planned stage remains unavailable")

func _test_distinct_roles_and_paths() -> void:
	var wrong := Simulation.new()
	wrong.reset("a", {}, pairs)
	_to_south(wrong)
	_check(wrong.snapshot().context_action.id == "reserved", "The first player cannot substitute for their partner at the South mirror")
	wrong.step({"interact":true})
	_check(wrong.snapshot().mirrors["south-mirror"] == "slash" and not wrong.can_commit(), "Pressing the reserved control cannot satisfy either first-turn source or whole-stage goal")
	var source := _source()
	first = source.export_recording()
	_check(source.can_commit() and source.snapshot().optics.signals["north-promise"] and not source.snapshot().optics.signals["south-promise"], "A's real upper-mirror action powers only its own North promise")
	_check(not source.complete and not source.snapshot().receiver_goal.unlocked, "One lit receiver cannot fabricate the two-input objective")
	var b := Simulation.new()
	b.reset("b", first, pairs)
	# Two opposite diagonal moves align B's eight-centimetre control lattice
	# with A's inherited Z coordinate without changing its X coordinate.
	_move(b, [-80,0])
	b.step({"move_x":1,"move_z":1})
	b.step({"move_x":-1,"move_z":1})
	_move(b, [-80,60])
	while b.tick < first.duration_ticks:
		b.step({})
	var state := b.snapshot()
	_check(state.players.p0.x == state.players.p1.x and state.players.p0.z == state.players.p1.z, "B can actually occupy the recorded keeper's position without blocking or pushing it")
	b.step({"interact":true})
	b.step({})
	_check(b.snapshot().mirrors["upper-mirror"] == "backslash" and b.snapshot().optics.signals["north-promise"], "B cannot extinguish or rotate the source-owned upper mirror")
	_check(Canonical.same(_bare(b.snapshot().players.p0), _bare(source.snapshot().players.p0)), "The independently replayed ghost endpoint remains exact")

func _test_simultaneous_signals() -> void:
	var delayed := _source(180)
	var delayed_record: Dictionary = delayed.export_recording()
	var b := Simulation.new()
	b.reset("b", delayed_record, pairs)
	_to_south(b)
	b.step({"interact":true})
	var lower_only := b.snapshot()
	_check(lower_only.optics.signals["south-promise"] and not lower_only.optics.signals["north-promise"] and not lower_only.objective_done, "B can align South first, but a single lower input does not unlock the selector")
	b.step({})
	b.step({"interact":true})
	b.step({})
	while b.tick < 190:
		b.step({})
	_check(b.snapshot().optics.signals["north-promise"] and not b.snapshot().optics.signals["south-promise"] and not b.snapshot().objective_done, "Seeing each receiver at different times does not count as simultaneous cooperation")
	b.step({"interact":true})
	_check(b.snapshot().objective_done and b.snapshot().receiver_goal.unlocked and b.snapshot().receiver_goal.signals["north-promise"] and b.snapshot().receiver_goal.signals["south-promise"], "Only the actual two-live-input state unlocks the objective")
	while not b.finished:
		b.step({})
	_check(b.complete and b.tick == delayed_record.duration_ticks, "Completion consumes the exact source length without an added goal waiting timer")
	_check(not Simulation.new().reset("b", delayed_record, [pairs[0]]), "The third-stage source cannot be attached to an incomplete chapter prefix")

func _test_resume_and_checkpoint() -> void:
	var b := Simulation.new()
	b.reset("b", first, pairs)
	_to_south(b)
	var draft := b.export_recording()
	_check(b.snapshot().players.p1.surface_id == "south" and b.snapshot().context_action.id == "rotate", "A real South crossing reaches the separately owned second control")
	_check(Simulation.verify_recording(draft, first, pairs).valid and not b.can_commit(), "An unfinished one-input draft verifies without becoming a completion")
	var resumed := Simulation.new()
	_check(resumed.resume_recording(JSON.parse_string(JSON.stringify(draft)), first, pairs), "A JSON draft resumes the same source and South approach")
	_check(resumed.state_hash() == b.state_hash() and resumed.snapshot().events.is_empty(), "Resume restores every optical/player/prop state without replaying presentation events")
	var before := Canonical.digest(pairs)
	b.step({"interact":true})
	resumed.step({"interact":true})
	_check(b.complete and resumed.complete and Canonical.same(b.export_recording(), resumed.export_recording()), "Interrupted and uninterrupted final mirror actions produce the same complete record")
	second = b.export_recording()
	_check(second.schema_version == 3 and second.checkpoint_hash == checkpoints[2].checkpoint_hash and second.source_recording_hash == first.recording_hash, "Stage three binds both the exact derived start and full first-turn recording")
	var observed := b.state_hash()
	b.step({"interact":true,"move_x":1})
	_check(b.state_hash() == observed, "Repeated controls after finishing cannot move actors or rotate the solved mirrors")
	var full := pairs + [{"a":first,"b":second}]
	var result := Simulation.checkpoint_from_pairs(full)
	_check(result.valid and result.checkpoint.stage_index == 3 and result.checkpoint.mechanisms.flags.get("east-selector-powered") == true, "The verified pair derives a powered selector flag for the later timing stage")
	_check(result.checkpoint.mechanisms.latched_bridges == ["court-north","court-south","harbour-court"], "The checkpoint remembers only the three built routes, not the future eastern bridges")
	_check(Canonical.same(result.checkpoint.mechanisms.props["portable-lens"], checkpoints[2].mechanisms.props["portable-lens"]) and Canonical.digest(pairs) == before, "The exact fitted lens and immutable earlier evidence survive the dual-receiver solve")
	var next := Simulation.new()
	_check(next.reset("a", {}, full) and next.snapshot().stage_id == "after-the-first-bell", "The completed receiver pair starts the authored ordered-route stage through exact evidence")
	var replay := Simulation.new()
	replay.reset("b", first, pairs)
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		replay.step(input)
		for _i in range(replay.tick % 3):
			replay.snapshot()
	_check(Canonical.same(replay.export_recording(), second), "Variable render observation counts do not alter the cooperative light result")

func _test_source_deadline() -> void:
	var broken := _source()
	broken.step({"interact":true})
	broken.step({})
	broken.step({"interact":true})
	broken.step({})
	_check(broken.snapshot().optics.signals["north-promise"] and not broken.can_commit() and "interrupted" in broken.commit_reason(), "Turning away and back cannot erase interruption of A's first North promise")
	_check(not Simulation.new().reset("b", broken.export_recording(), pairs), "The later player cannot start from an unstable source despite its aligned endpoint")
	var probe := _source()
	var latest: int = Simulation.MAX_TICKS - probe.source_budget_ticks()
	var border := _source(latest)
	_check(border.snapshot().first_power_tick == latest and border.can_commit(), "The conservative source deadline uses the actual inherited receiver start")
	var b := Simulation.new()
	b.reset("b", border.export_recording(), pairs)
	while b.tick < latest:
		b.step({})
	_to_south(b)
	b.step({"interact":true})
	_check(b.complete and b.tick <= Simulation.MAX_TICKS, "Real controls can finish from the current endpoint even after the borderline alignment")
	var late := _source(latest+1)
	_check(not late.can_commit() and "earlier" in late.commit_reason() and not Simulation.new().reset("b",late.export_recording(),pairs), "One tick past the conservative alignment deadline is held rather than creating an impossible later turn")

func _test_negative_evidence() -> void:
	var forged := second.duplicate(true)
	forged.completed = false
	_rehash(forged)
	_check(not Simulation.verify_recording(forged,first,pairs).valid, "Rehashing an invented completion flag does not bypass the optical replay")
	forged = second.duplicate(true)
	forged.source_recording_hash = "4".repeat(64)
	_rehash(forged)
	_check(not Simulation.verify_recording(forged,first,pairs).valid, "The second role rejects an unrelated source hash")
	forged = second.duplicate(true)
	forged.checkpoint_hash = checkpoints[1].checkpoint_hash
	_rehash(forged)
	_check(not Simulation.verify_recording(forged,first,pairs).valid, "A rehashed older checkpoint cannot reinterpret current positions and fitted state")
	var changed := pairs.duplicate(true)
	changed[1].b.final_state_hash = "5".repeat(64)
	changed[1].b.recording_hash = Simulation.recording_hash(changed[1].b)
	_check(not Simulation.new().reset("a",{},changed), "The lens must come from the actual replayed earlier Fit, not a forged carried state")
	_check(not Simulation.new().reset("a",{},[checkpoints[2]]), "A self-hashed checkpoint alone does not replace linear pair evidence")
	forged = second.duplicate(true)
	forged.actions[-1].action = false
	_rehash(forged)
	_check(not Simulation.verify_recording(forged,first,pairs).valid, "Removing the actual final mirror action cannot retain the solved result")
	var previous := Simulation.new()
	previous.reset("b",first,pairs)
	previous.step({})
	_check(not previous.resume_recording(forged,first,pairs) and previous.export_recording().is_empty(), "A rejected resume cannot continue the old loaded engine")
	for bad: Dictionary in [{"complete":true},{"interact":"yes"},{"move_z":INF}]:
		var sim := Simulation.new()
		sim.reset("b",first,pairs)
		sim.step(bad)
		_check(sim.tick == 0 and sim.export_recording().is_empty(), "Unsupported controls cannot advance ghost state or satisfy receiver goals")

func _test_north_endpoint() -> void:
	var alternative := _pairs_with_receiver_in_north()
	var prior := Simulation.checkpoint_from_pairs(alternative)
	_check(prior.valid and prior.checkpoint.players.p1.surface_id == "north", "A valid earlier source may finish on North instead of at the Court mirror")
	var source := _source(0,alternative)
	var b := Simulation.new()
	b.reset("b",source.export_recording(),alternative)
	_check(Canonical.same(_bare(b.snapshot().players.p1),prior.checkpoint.players.p1), "The later player keeps that exact remote endpoint")
	_to_south(b)
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	_check(b.complete and Simulation.verify_recording(b.export_recording(),source.export_recording(),alternative).valid, "The same spatial objective succeeds through the real remembered North–Court–South route")

func _source(first_alignment_tick: int = 0, evidence: Array = []) -> RefCounted:
	var sim := Simulation.new()
	sim.reset("a",{},pairs if evidence.is_empty() else evidence)
	_move(sim,[-80,60])
	while sim.tick < first_alignment_tick - 1:
		sim.step({})
	sim.step({"interact":true})
	for _i in range(20):
		sim.step({})
	return sim

func _to_south(sim: RefCounted) -> void:
	var state: Dictionary = sim.snapshot()
	var player: Dictionary = state.players[state.active_slot]
	if player.surface_id in ["harbour","harbour-court"]:
		_move(sim,[int(player.x),0])
		_move(sim,[-48,0])
	else:
		_move(sim,[-48,int(player.z)])
	_move(sim,[-48,352])
	_move(sim,[56,352])

func _pairs_with_receiver_in_north() -> Array:
	var prefix := [pairs[0]]
	var a := Simulation.new()
	a.reset("a",{},prefix)
	_move(a,[-80,64])
	_move(a,[-80,0])
	a.step({"interact":true})
	a.step({})
	_move(a,[-48,0])
	_move(a,[-48,-352])
	_move(a,[56,-352])
	var b := Simulation.new()
	b.reset("b",a.export_recording(),prefix)
	var player: Dictionary = b.snapshot().players.p0
	_move(b,[player.x,0])
	_move(b,[-48,0])
	_move(b,[-48,-356])
	_move(b,[40,-356])
	b.step({"interact":true})
	b.step({})
	_move(b,[-48,-356])
	_move(b,[-48,60])
	_move(b,[40,60])
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	return prefix + [{"a":a.export_recording(),"b":b.export_recording()}]

func _move(sim: RefCounted, destination: Array) -> void:
	for _i in range(200):
		if sim.finished:
			return
		var state: Dictionary = sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		if absi(dx) <= 4 and absi(dz) <= 4:
			return
		sim.step({"move_x":signi(dx) if absi(dx)>4 else 0,"move_z":0 if absi(dx)>4 else signi(dz)})

func _bare(player: Dictionary) -> Dictionary:
	return {"x":player.x,"z":player.z,"surface_id":player.surface_id}

func _rehash(record: Dictionary) -> void:
	record.recording_hash = Simulation.recording_hash(record)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
