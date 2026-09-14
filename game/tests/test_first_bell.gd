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
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-three-v3.json"))
	if not fixture is Dictionary or not fixture.get("pairs") is Array or fixture.pairs.size() != 3 or not fixture.get("checkpoints") is Array or fixture.checkpoints.size() != 4:
		_check(false, "The preserved first-three-stage recordings and checkpoints are present")
		_finish()
		return
	pairs = fixture.pairs
	checkpoints = fixture.checkpoints
	_test_old_records()
	_test_geometry_and_source_ownership()
	_test_invalid_windows()
	_test_generous_route()
	_test_occupied_footprint_and_resume()
	_test_missed_window()
	_test_deadline()
	_test_proof_and_tampering()
	_test_remote_endpoint()
	_check(checks >= 50 and not second.is_empty(), "Every timing, safety, checkpoint and negative test group executed")
	_finish()

func _finish() -> void:
	print("AFTER YOU FIRST BELL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_old_records() -> void:
	var prefix: Array = []
	_check(Canonical.same(Simulation.initial_checkpoint(), checkpoints[0]), "The initial checkpoint is unchanged")
	for index in range(3):
		var pair: Dictionary = pairs[index]
		for role: String in ["a", "b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			var checked := Simulation.verify_recording(pair[role], prior, prefix)
			_check(checked.valid, "An exact frozen earlier recording still verifies")
			var sim := Simulation.new()
			sim.reset(role, prior, prefix)
			for frame: Dictionary in Simulation.expand_recording_inputs(pair[role]):
				sim.step(frame)
			_check(Canonical.same(sim.export_recording(), pair[role]), "Replaying old controls preserves the complete old recording, not only the outcome")
		prefix.append(pair)
		var derived := Simulation.checkpoint_from_pairs(prefix)
		_check(derived.valid and Canonical.same(derived.checkpoint, checkpoints[index+1]), "The exact earlier checkpoint remains compatible")

func _test_geometry_and_source_ownership() -> void:
	var sim := Simulation.new()
	_check(sim.reset("a",{},pairs), "Stage four loads only from all three verified earlier pairs")
	var state := sim.snapshot()
	_check(state.stage_id == "after-the-first-bell" and state.first_player_slot == "p1" and state.active_slot == "p1", "The first role alternates to the physical South player")
	_check(Canonical.same(_bare(state.players.p0),checkpoints[3].players.p0) and Canonical.same(_bare(state.players.p1),checkpoints[3].players.p1), "Both players retain their exact third-stage endpoints")
	_check(state.props["portable-lens"].status == "fitted" and checkpoints[3].mechanisms.flags["east-selector-powered"], "The selector depends on the actual earlier fitted lens and simultaneous light result")
	_check(sim.walkable_at(288,0) and sim.walkable_at(552,0) and not sim.walkable_at(192,0) and not sim.walkable_at(392,0), "Rest Rock and tower are real islands separated by two actual closed gaps")
	_check(not state.bridges["court-rest"] and not state.bridges["rest-tower"] and state.sequence.phase == "off", "The inherited two-receiver objective does not blanket-open new eastern routes")
	_to_selector(sim)
	sim.step({"interact":true})
	_check(sim.snapshot().optics.signals["first-path"] and not sim.snapshot().optics.signals["second-path"], "The first selector choice physically reflects light toward only its first receiver")
	_move(sim,[-48,352])
	_move(sim,[-48,0])
	_move(sim,[192,0])
	_check(sim.snapshot().players.p1.surface_id == "court" and sim.snapshot().players.p1.x <= 138 and sim.snapshot().route_progress.step == 0, "A stays on permanent floor and cannot pre-cross the later player's timed bridge")
	var source := _source()
	first = source.export_recording()
	var b := Simulation.new()
	b.reset("b",first,pairs)
	_to_selector(b)
	_check(b.snapshot().context_action.id == "reserved", "The later player can see but cannot operate their partner's selector")
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	_check(b.snapshot().selectors["south-selector"] == 2 and Canonical.same(_bare(b.snapshot().players.p1),_bare(source.snapshot().players.p1)) and not b.complete, "Later controls cannot rewrite the independently replayed source or invent a crossing")

func _test_invalid_windows() -> void:
	var probe := Simulation.new()
	probe.reset("a",{},pairs)
	var budgets := probe.sequence_budget_ticks()
	_check(budgets.size() == 2 and budgets[0] > 18 and budgets[1] > 18, "Both window budgets include real routes and a non-perfect-timing margin")
	var short_first := _source(0,int(budgets[0])-1,int(budgets[1]))
	_check(not short_first.can_commit() and "first path" in short_first.commit_reason() and not Simulation.new().reset("b",short_first.export_recording(),pairs), "A one-tick-short first window cannot become an accepted handoff")
	var short_second := _source(0,int(budgets[0]),int(budgets[1])-1)
	_check(not short_second.can_commit() and "second path" in short_second.commit_reason() and not Simulation.new().reset("b",short_second.export_recording(),pairs), "A one-tick-short second window is rejected independently")
	var only_first := Simulation.new()
	only_first.reset("a",{},pairs)
	_to_selector(only_first)
	only_first.step({"interact":true})
	for _i in range(int(budgets[0])):
		only_first.step({})
	_check(not only_first.can_commit() and "Select the second" in only_first.commit_reason(), "One long first phase cannot stand in for the ordered second part")
	var restarted := _source()
	restarted.step({"interact":true})
	restarted.step({})
	restarted.step({"interact":true})
	restarted.step({})
	restarted.step({"interact":true})
	restarted.step({})
	_check(restarted.snapshot().sequence.broken and restarted.snapshot().sequence.phase == "second" and not restarted.can_commit(), "Returning to the correct final selector position cannot erase a dark/restarted source sequence")
	_check(Simulation.verify_recording(restarted.export_recording(),{},pairs).valid and not Simulation.new().reset("b",restarted.export_recording(),pairs), "An honest failed source remains a replayable draft, not a viable B source")

func _test_generous_route() -> void:
	var a := _source()
	first = a.export_recording()
	_check(a.can_commit() and a.snapshot().sequence.first_ticks == a.sequence_budget_ticks()[0] and a.snapshot().sequence.second_ticks == a.sequence_budget_ticks()[1], "The shortest conservative two-window contribution is viable without a fixed stage timer")
	var b := Simulation.new()
	b.reset("b",first,pairs)
	# A receiver may react a third of a second late, then still reach safe Rest
	# Rock during the first window; this is deliberately not a perfect solver.
	for _i in range(10):
		b.step({})
	_to_rest(b)
	_check(b.snapshot().players.p0.surface_id == "rest-rock" and b.snapshot().route_progress.rest_reached and b.snapshot().sequence.phase == "first", "Actual movement with reaction delay reaches safe Rest Rock before the second phase")
	_check(not b.complete and not b.snapshot().objective_done and not b.snapshot().bridges["rest-tower"], "Reaching the checkpoint island cannot finish or prematurely open the second route")
	b.step({"interact":true})
	_check(not b.snapshot().objective_done, "Pressing Action on Rest Rock cannot ring the distant tower bell")
	while b.snapshot().sequence.phase != "second" and not b.finished:
		b.step({})
	_move(b,[552,0])
	_check(b.snapshot().route_progress.step == 4 and b.snapshot().context_action.id == "anchor" and b.snapshot().context_action.enabled, "The tower bell is enabled only after both real crossings and the intermediate island")
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	second = b.export_recording()
	_check(b.complete and b.can_commit() and Simulation.verify_recording(second,first,pairs).valid, "The actual source-and-receiver route completes and replay-verifies")
	_check(Canonical.same(_bare(b.snapshot().players.p1),_bare(a.snapshot().players.p1)), "The receiver's earned latches never alter the ghost's final physical position")

func _test_occupied_footprint_and_resume() -> void:
	var b := Simulation.new()
	b.reset("b",first,pairs)
	_to_court_line(b)
	_move(b,[144,0])
	var touching := b.snapshot()
	_check(touching.players.p0.surface_id == "court" and "court-rest" in touching.route_progress.kept_bridges, "A first footprint over the gap latches the bridge before the centre leaves Court")
	while b.snapshot().sequence.phase != "second" and not b.finished:
		b.step({})
	_check(not b.snapshot().optics.signals["first-path"] and b.snapshot().bridges["court-rest"] and b.walkable_at(int(b.snapshot().players.p0.x),int(b.snapshot().players.p0.z)), "A recorded selector change cannot remove the floor beneath an occupied footprint")
	var draft := b.export_recording()
	var resumed := Simulation.new()
	_check(resumed.resume_recording(JSON.parse_string(JSON.stringify(draft)),first,pairs), "A draft resumes after the first window closed with the exact earned floor intact")
	_check(resumed.state_hash() == b.state_hash() and resumed.snapshot().events.is_empty(), "Safe-floor, selector schedule and route progress all survive silent reconstruction")
	for sim: RefCounted in [b,resumed]:
		_move(sim,[288,0])
		_move(sim,[552,0])
		sim.step({"interact":true})
		while not sim.finished:
			sim.step({})
	_check(b.complete and resumed.complete and Canonical.same(b.export_recording(),resumed.export_recording()), "Interrupted and uninterrupted movement produce exactly the same completed record")
	var unchanged := b.state_hash()
	b.step({"move_x":1,"interact":true})
	_check(b.state_hash() == unchanged, "Finished input cannot move a saved endpoint or re-trigger a bell")

func _test_missed_window() -> void:
	var b := Simulation.new()
	b.reset("b",first,pairs)
	while b.snapshot().sequence.phase != "second" and not b.finished:
		b.step({})
	_to_court_line(b)
	_move(b,[288,0])
	_check(b.snapshot().players.p0.surface_id == "court" and b.snapshot().players.p0.x <= 138 and b.snapshot().route_progress.step == 0, "A completely missed first window holds B on Court instead of pretending a route exists")
	_check(not b.snapshot().bridges["court-rest"] and b.snapshot().bridges["rest-tower"] and not b.can_commit(), "The second light does not repair an unentered first bridge or grant completion")
	var fresh := Simulation.new()
	_check(fresh.reset("b",first,pairs) and not fresh.snapshot().route_progress.rest_reached, "Retrying B keeps the immutable source and resets only this failed crossing attempt")

func _test_deadline() -> void:
	var ordinary := _source()
	var extra: int = Simulation.MAX_TICKS - ordinary.tick
	var last := _source(extra)
	_check(last.finished and last.tick == Simulation.MAX_TICKS and last.can_commit(), "An exact final-tick source remains viable when both recorded windows are complete")
	var b := Simulation.new()
	b.reset("b",last.export_recording(),pairs)
	while b.tick < extra:
		b.step({})
	_to_rest(b)
	while b.snapshot().sequence.phase != "second" and not b.finished:
		b.step({})
	_move(b,[552,0])
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	_check(b.complete and b.tick == Simulation.MAX_TICKS, "Real movement succeeds even with the conservative schedule ending at the recording limit")
	var late := _source(extra+1)
	_check(late.finished and not late.can_commit() and not Simulation.new().reset("b",late.export_recording(),pairs), "One tick past the recording limit cannot fake the missing second window")

func _test_proof_and_tampering() -> void:
	var prefix_hash := Canonical.digest(pairs)
	var full := pairs + [{"a":first,"b":second}]
	var cp := Simulation.checkpoint_from_pairs(full)
	_check(cp.valid and cp.checkpoint.stage_index == 4 and cp.checkpoint.mechanisms.flags["east-selector-powered"] and cp.checkpoint.mechanisms.flags["tower-anchor-lit"], "The completed ordered route preserves earlier proof and derives the new tower flag")
	_check(cp.checkpoint.mechanisms.latched_bridges == ["court-north","court-rest","court-south","harbour-court","rest-tower"], "Only the five actual traversable bridges are remembered for later carrying")
	_check(Canonical.same(cp.checkpoint.mechanisms.props,checkpoints[3].mechanisms.props) and Canonical.digest(pairs) == prefix_hash, "The carried lens state and every earlier immutable record remain unchanged")
	var next := Simulation.new()
	_check(next.reset("a",{},full) and next.snapshot().stage_id == "what-carried-you" and Catalog.definition("unknown-stage").is_empty(), "The verified remembered paths start the transfer stage without allowing unauthored stages")
	var bad := first.duplicate(true)
	bad.actions[0].ticks += 1
	bad.duration_ticks += 1
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,{},pairs).valid, "Rehashing a changed sequence timing cannot reuse the original replay checks")
	bad = second.duplicate(true)
	bad.source_recording_hash = "8".repeat(64)
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,first,pairs).valid, "A receiver cannot bind a different source schedule")
	bad = second.duplicate(true)
	bad.checkpoint_hash = checkpoints[2].checkpoint_hash
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,first,pairs).valid, "An older self-consistent checkpoint hash cannot discard the dual-receiver prerequisite")
	bad = second.duplicate(true)
	bad.completed = false
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,first,pairs).valid, "The full source hash does not excuse a fabricated completion flag")
	_check(not Simulation.new().reset("a",{},[checkpoints[3]]), "A state-only checkpoint cannot unlock timed route mechanics")
	var invalid := Simulation.new()
	invalid.reset("b",first,pairs)
	invalid.step({"anchor":true})
	_check(invalid.tick == 0 and invalid.export_recording().is_empty(), "A caller cannot invoke the tower objective through an unsupported input")

func _test_remote_endpoint() -> void:
	var prefix := [pairs[0],pairs[1]]
	var a := Simulation.new()
	a.reset("a",{},prefix)
	_move(a,[-80,60])
	a.step({"interact":true})
	a.step({})
	_move(a,[-48,60])
	_move(a,[-48,-352])
	_move(a,[56,-352])
	var b := Simulation.new()
	b.reset("b",a.export_recording(),prefix)
	_to_selector(b)
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	var remote := prefix + [{"a":a.export_recording(),"b":b.export_recording()}]
	var cp := Simulation.checkpoint_from_pairs(remote)
	_check(cp.valid and cp.checkpoint.players.p0.surface_id == "north", "A legitimate third-stage source can leave the next receiver at its actual North endpoint")
	var source := _source(0,-1,-1,remote)
	var receiver := Simulation.new()
	receiver.reset("b",source.export_recording(),remote)
	_check(Canonical.same(_bare(receiver.snapshot().players.p0),cp.checkpoint.players.p0) and source.sequence_budget_ticks()[0] > _source().sequence_budget_ticks()[0], "The first route budget grows with the inherited North approach rather than resetting the player")
	_to_rest(receiver)
	_check(receiver.snapshot().players.p0.surface_id == "rest-rock" and receiver.snapshot().sequence.phase == "first", "The authored North–Court–Rest route really fits its first recorded window")
	while receiver.snapshot().sequence.phase != "second" and not receiver.finished:
		receiver.step({})
	_move(receiver,[552,0])
	receiver.step({"interact":true})
	while not receiver.finished:
		receiver.step({})
	_check(receiver.complete and Simulation.verify_recording(receiver.export_recording(),source.export_recording(),remote).valid, "The same two-gap puzzle completes from a different verified physical endpoint")

func _source(delay: int = 0, first_ticks: int = -1, second_ticks: int = -1, evidence: Array = []) -> RefCounted:
	var sim := Simulation.new()
	sim.reset("a",{},pairs if evidence.is_empty() else evidence)
	_to_selector(sim)
	var budgets := sim.sequence_budget_ticks()
	for _i in range(delay):
		sim.step({})
	sim.step({"interact":true})
	var first_length: int = budgets[0] if first_ticks < 0 else first_ticks
	var second_length: int = budgets[1] if second_ticks < 0 else second_ticks
	while sim.snapshot().sequence.first_ticks < first_length and not sim.finished:
		sim.step({})
	sim.step({"interact":true})
	while sim.snapshot().sequence.second_ticks < second_length and not sim.finished:
		sim.step({})
	return sim

func _to_selector(sim: RefCounted) -> void:
	var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
	if player.surface_id == "south" and absi(int(player.x)-56) <= 4 and absi(int(player.z)-352) <= 4:
		return
	if player.surface_id in ["harbour","harbour-court"]:
		_move(sim,[int(player.x),0])
		_move(sim,[-48,0])
	else:
		_move(sim,[-48,int(player.z)])
	_move(sim,[-48,352])
	_move(sim,[56,352])

func _to_court_line(sim: RefCounted) -> void:
	var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
	if player.surface_id in ["north","court-north","south","court-south"]:
		_move(sim,[-48,int(player.z)])
		_move(sim,[-48,0])
	else:
		_move(sim,[int(player.x),0])

func _to_rest(sim: RefCounted) -> void:
	_to_court_line(sim)
	_move(sim,[288,0])

func _move(sim: RefCounted, destination: Array) -> void:
	for _i in range(200):
		if sim.finished:
			return
		var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
		var dx := int(destination[0])-int(player.x)
		var dz := int(destination[1])-int(player.z)
		if absi(dx) <= 4 and absi(dz) <= 4:
			return
		sim.step({"move_x":signi(dx) if absi(dx)>4 else 0,"move_z":0 if absi(dx)>4 else signi(dz)})

func _bare(player: Dictionary) -> Dictionary:
	return {"x":player.x,"z":player.z,"surface_id":player.surface_id}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
