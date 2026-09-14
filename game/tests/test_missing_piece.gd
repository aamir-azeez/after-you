extends SceneTree

const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Catalog = preload("res://core/lighthouse/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var prior: Array = []
var checkpoint: Dictionary = {}
var first: Dictionary = {}
var second: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_verified_start()
	_test_physical_lens_route()
	_test_resume_and_replay()
	_test_source_viability()
	_test_invalid_evidence()
	_test_alternate_endpoints()
	_check(checks >= 50 and not second.is_empty(), "All stage-two groups reached their real completion assertions")
	print("AFTER YOU MISSING PIECE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_verified_start() -> void:
	prior = [_borrowed_pair()]
	var derived := Simulation.checkpoint_from_pairs(prior)
	_check(derived.valid, "The exact first-stage A/B pair derives a chapter checkpoint")
	checkpoint = derived.checkpoint
	_check(checkpoint.stage_index == 1 and checkpoint.mechanisms.latched_bridges == ["harbour-court"], "Only the completed route is remembered at the first checkpoint")
	var initial := Simulation.initial_checkpoint()
	_check(checkpoint.previous_checkpoint_hash == initial.checkpoint_hash and checkpoint.a_recording_hash == prior[0].a.recording_hash and checkpoint.b_recording_hash == prior[0].b.recording_hash, "The checkpoint binds its predecessor and both full recordings")
	var sim := Simulation.new()
	_check(sim.reset("a", {}, prior), "Stage two starts only after verified first-stage evidence")
	_check(sim.snapshot().stage_id == "missing-piece" and sim.snapshot().active_slot == "p1", "Roles reverse while physical player identities stay fixed")
	_check(Canonical.same(_bare(sim.snapshot().players.p0), checkpoint.players.p0) and Canonical.same(_bare(sim.snapshot().players.p1), checkpoint.players.p1), "Both players keep exact prior endpoints without spawn teleportation")
	_check(sim.snapshot().players.p1.x == 0 and sim.snapshot().players.p1.z == 64, "A non-bell endpoint survives the stage transition")
	_check(sim.walkable_at(-350, 0) and not sim.walkable_at(-48, -180) and sim.walkable_at(40, -360), "The old crossing is remembered, the new North gap is closed, and North is a real separate surface")
	_move(sim, [-48,64])
	_move(sim, [-48,-120])
	_check(sim.snapshot().players.p1.z >= -118 and not sim.can_commit(), "A control-driven attempt cannot tunnel across the closed North gap")
	_check(sim.snapshot().props["portable-lens"].status == "pedestal", "The lens begins on its authored North pedestal")
	_check(Catalog.definition("unknown-stage").is_empty() and Catalog.STAGE_IDS.size() == 6, "Only the six authored Lighthouse stages are available")

func _test_physical_lens_route() -> void:
	var a := _aligned_source()
	first = a.export_recording()
	_check(a.can_commit() and a.snapshot().bridges["court-north"], "A's real mirror interaction leaves the North crossing open")
	_check(first.schema_version == 3 and first.simulation_version == 3 and first.player_slot == "p1" and first.checkpoint_hash == checkpoint.checkpoint_hash, "Stage two stays on schema three and explicitly binds its verified checkpoint")
	_check(Simulation.verify_recording(first, {}, prior).valid, "The new first turn verifies through the earlier chapter pair")
	_check(not Simulation.verify_recording(first).valid, "Stage-two recordings cannot silently reset to first-stage spawns")
	var b := Simulation.new()
	_check(b.reset("b", first, prior) and b.snapshot().active_slot == "p0", "The receiver starts as the same physical p0 from the prior stage")
	_to_court(b)
	_move(b, [-80,0])
	_check(b.snapshot().context_action.id == "reserved" and not b.snapshot().context_action.enabled, "B sees the source-owned mirror as reserved")
	var source_hash := Canonical.digest(first)
	b.step({"interact": true})
	b.step({})
	_check(b.snapshot().mirrors["court-mirror"] == "slash" and b.snapshot().bridges["court-north"], "B cannot extinguish the ghost's aligned source")
	_check(Canonical.same(_bare(b.snapshot().players.p1), _bare(a.snapshot().players.p1)), "The ghost holds its independently replayed physical endpoint")
	_move(b, [-48,0])
	_move(b, [-48,64])
	_move(b, [40,64])
	_check(b.snapshot().context_action.id == "fit" and not b.snapshot().context_action.enabled, "An empty-handed player cannot fit a lens at the nearby cradle")
	b.step({"interact": true})
	b.step({})
	_check(not b.snapshot().objective_done, "Pressing Fit without possession cannot fabricate completion")
	_to_lens(b)
	_check(b.snapshot().players.p0.surface_id == "north" and b.snapshot().context_action.id == "take", "The player physically crosses into North to reach Take lens")
	b.step({"interact": true})
	for _i in range(4):
		b.step({"interact": true})
	_check(b.snapshot().props.size() == 1 and b.snapshot().props["portable-lens"].status == "carried" and b.snapshot().props["portable-lens"].holder_slot == "p0", "Repeated held input takes exactly one lens into the correct holder")
	_check(b.snapshot().bridges["court-north"], "Taking the lens leaves the return path powered")
	b.step({})
	var draft := b.export_recording()
	_check(Simulation.verify_recording(draft, first, prior).valid and not b.can_commit(), "A carried-lens draft verifies without becoming a completed turn")
	var resumed := Simulation.new()
	_check(resumed.resume_recording(JSON.parse_string(JSON.stringify(draft)), first, prior), "A JSON-reloaded carried-lens draft resumes from recorded inputs")
	_check(Canonical.same(resumed.snapshot().props, b.snapshot().props) and resumed.state_hash() == b.state_hash() and resumed.snapshot().events.is_empty(), "Resume restores exact holder and simulation state while suppressing old presentation events")
	_return_lens(b)
	_return_lens(resumed)
	_check(Canonical.same(b.export_recording(), resumed.export_recording()), "Interrupted and uninterrupted carrying produce identical complete recordings")
	second = b.export_recording()
	_check(b.complete and b.can_commit() and b.snapshot().props["portable-lens"].status == "fitted", "A real return and Fit interaction completes the second stage")
	_check(b.snapshot().props["portable-lens"].holder_slot == "" and b.snapshot().props["portable-lens"].socket_id == "court-cradle", "The fitted lens belongs to its socket and no longer to a player")
	_check(Canonical.digest(first) == source_hash, "Carrying, fitting and resumed playback leave source recording bytes unchanged")
	var final := Simulation.checkpoint_from_pairs(prior + [{"a": first, "b": second}])
	_check(final.valid and final.checkpoint.stage_index == 2 and final.checkpoint.mechanisms.latched_bridges == ["court-north", "harbour-court"], "The completed second pair remembers both physical paths")
	_check(final.checkpoint.mechanisms.props["portable-lens"].status == "fitted" and Canonical.same(final.checkpoint.players.p0, _bare(b.snapshot().players.p0)), "The next checkpoint preserves the fitted prop and exact player endpoint")
	var third := Simulation.new()
	_check(third.reset("a", {}, prior + [{"a": first, "b": second}]) and third.snapshot().stage_id == "two-promises", "The completed lens pair starts the authored third stage through its exact evidence")

func _test_resume_and_replay() -> void:
	var replay := Simulation.new()
	replay.reset("b", first, prior)
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		replay.step(input)
		for _i in range(replay.tick % 4):
			replay.snapshot()
	_check(Canonical.same(replay.export_recording(), second), "Different render observation rates leave the lens result deterministic")
	var completed_hash := replay.state_hash()
	replay.step({"interact": true, "move_x": -1})
	_check(replay.state_hash() == completed_hash, "Repeated inputs after completion cannot duplicate or remove the fitted lens")
	var stopped := Simulation.new()
	stopped.reset("b", first, prior)
	stopped.step({})
	var saved := stopped.export_recording()
	for _i in range(8):
		stopped.snapshot()
	_check(Canonical.same(saved, stopped.export_recording()), "Pausing without simulation ticks changes neither draft nor ghost time")
	var malformed := second.duplicate(true)
	malformed.completed = false
	_rehash(malformed)
	_check(not Simulation.verify_recording(malformed, first, prior).valid, "A rehashed false completion claim cannot replace the actual result")
	malformed = second.duplicate(true)
	malformed.final_state_hash = "1".repeat(64)
	_rehash(malformed)
	_check(not Simulation.verify_recording(malformed, first, prior).valid, "A forged fitted-lens state hash is rejected by replay")
	malformed = second.duplicate(true)
	malformed.actions[0].x = 1
	_rehash(malformed)
	_check(not Simulation.verify_recording(malformed, first, prior).valid, "Rehashed action tampering cannot preserve an unrelated checkpoint or lens outcome")
	_check(not replay.resume_recording(malformed, first, prior) and replay.export_recording().is_empty(), "Failed resume unloads the previous valid completed turn")
	var exposed := Simulation.new()
	exposed.reset("b", first, prior)
	var state := exposed.state_hash()
	var snapshot := exposed.snapshot()
	snapshot.props["portable-lens"].status = "fitted"
	snapshot.players.p0.x = 40
	_check(exposed.state_hash() == state and not exposed.snapshot().objective_done, "Mutating a returned snapshot cannot move a player or fit a prop")

func _test_source_viability() -> void:
	var wrong := Simulation.new()
	wrong.reset("a", {}, prior)
	for _i in range(25):
		wrong.step({"interact": true})
	_check(not wrong.can_commit() and not Simulation.new().reset("b", wrong.export_recording(), prior), "An idle wrong-facing mirror is not a viable source")
	var broken := _aligned_source()
	broken.step({"interact": true})
	broken.step({})
	broken.step({"interact": true})
	broken.step({})
	_check(broken.snapshot().bridges["court-north"] and not broken.can_commit() and "interrupted" in broken.commit_reason(), "Turning away and back cannot erase interruption of the first usable alignment")
	_check(not Simulation.new().reset("b", broken.export_recording(), prior), "B rejects an apparently aligned endpoint with an interrupted source history")
	var probe := _aligned_source()
	var latest: int = Simulation.MAX_TICKS - probe.source_budget_ticks()
	var border := _aligned_source(latest)
	_check(border.snapshot().first_power_tick == latest and border.can_commit(), "The exact conservative source deadline is accepted")
	var b := Simulation.new()
	b.reset("b", border.export_recording(), prior)
	for _i in range(latest):
		b.step({})
	_to_lens(b)
	b.step({"interact": true})
	b.step({})
	_return_lens(b)
	_check(b.complete and b.tick <= Simulation.MAX_TICKS, "The actual receiver controls complete even when starting after the borderline alignment")
	var late := _aligned_source(latest + 1)
	_check(not late.can_commit() and "earlier" in late.commit_reason(), "A source one tick later is held with a useful reason")
	_check(not Simulation.new().reset("b", late.export_recording(), prior), "Over-late alignment never starts the dependent receiver turn")

func _test_invalid_evidence() -> void:
	var changed := prior.duplicate(true)
	changed[0].b.completed = false
	changed[0].b.recording_hash = Simulation.recording_hash(changed[0].b)
	_check(not Simulation.checkpoint_from_pairs(changed).valid, "Rehashing a prior pair's false outcome cannot derive a checkpoint")
	_check(not Simulation.new().reset("a", {}, [checkpoint]), "A checkpoint dictionary cannot stand in for its original pair evidence")
	_check(not Simulation.checkpoint_from_pairs(prior + prior).valid, "Duplicating the first pair cannot advance the chapter twice")
	_check(not Simulation.checkpoint_from_pairs([{"a": prior[0].b, "b": prior[0].a}]).valid, "Reversing pair order is rejected")
	_check(not Simulation.checkpoint_from_pairs([{"a": prior[0].a, "b": prior[0].b, "players": checkpoint.players}]).valid, "Extra caller-authored checkpoint state is rejected")
	var unknown := first.duplicate(true)
	unknown.stage_id = "unknown"
	_rehash(unknown)
	_check(not Simulation.verify_recording(unknown, {}, prior).valid, "Unknown stage IDs cannot reach a generic fallback simulation")
	unknown = first.duplicate(true)
	unknown.checkpoint_hash = "2".repeat(64)
	_rehash(unknown)
	_check(not Simulation.verify_recording(unknown, {}, prior).valid, "A rehashed altered checkpoint dependency is rejected")
	unknown = second.duplicate(true)
	unknown.player_slot = "p1"
	_rehash(unknown)
	_check(not Simulation.verify_recording(unknown, first, prior).valid, "A recording cannot change its physical player slot")
	var replacement: Dictionary = _aligned_source(0, 1).export_recording()
	_check(not Simulation.verify_recording(second, replacement, prior).valid, "A new equivalent alignment recording still invalidates its dependent B")
	var changed_pair := [_borrowed_pair(true)]
	_check(not Simulation.verify_recording(first, {}, changed_pair).valid, "A different valid prior pair invalidates the stage-two recording")
	for bad: Dictionary in [{"fit": true}, {"interact": "yes"}, {"move_x": INF}]:
		var sim := Simulation.new()
		sim.reset("b", first, prior)
		sim.step(bad)
		_check(sim.tick == 0 and sim.export_recording().is_empty(), "Malformed input cannot advance source playback or fabricate lens actions")

func _test_alternate_endpoints() -> void:
	var alternate := [_borrowed_pair(true)]
	var derived := Simulation.checkpoint_from_pairs(alternate)
	_check(derived.valid and derived.checkpoint.players.p1.surface_id == "harbour", "A legitimate return to Harbour after ringing remains a valid endpoint")
	var a := Simulation.new()
	a.reset("a", {}, alternate)
	_check(Canonical.same(_bare(a.snapshot().players.p1), derived.checkpoint.players.p1), "Role reversal preserves an endpoint away from the next control")
	_to_court(a)
	_move(a, [-80,0])
	a.step({"interact": true})
	for _i in range(20):
		a.step({})
	_check(a.can_commit(), "Real controls can reach and align the Court mirror from that preserved Harbour endpoint")
	var b := Simulation.new()
	b.reset("b", a.export_recording(), alternate)
	_to_lens(b)
	b.step({"interact": true})
	b.step({})
	_return_lens(b)
	_check(b.complete, "The lens stage also completes from a non-default prior pair")

func _borrowed_pair(return_home: bool = false) -> Dictionary:
	var a := Simulation.new()
	a.reset()
	for _i in range(4):
		a.step({"move_x": 1})
	while a.tick < (300 if return_home else 200):
		a.step({})
	var b := Simulation.new()
	b.reset("b", a.export_recording())
	_move(b, [-560,80])
	_move(b, [-560,-96])
	b.step({"interact": true})
	b.step({})
	_move(b, [-560,0])
	_move(b, [-160,0])
	b.step({"interact": true})
	b.step({})
	_move(b, [-560,0] if return_home else [0,0])
	if not return_home:
		_move(b, [0,64])
	while not b.finished:
		b.step({})
	return {"a": a.export_recording(), "b": b.export_recording()}

func _aligned_source(first_alignment_tick: int = 0, extra_ticks: int = 0) -> RefCounted:
	var sim := Simulation.new()
	sim.reset("a", {}, prior)
	_move(sim, [-80,64])
	_move(sim, [-80,0])
	while sim.tick < first_alignment_tick - 1:
		sim.step({})
	sim.step({"interact": true})
	for _i in range(20 + extra_ticks):
		sim.step({})
	return sim

func _to_court(sim: RefCounted) -> void:
	var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
	_move(sim, [int(player.x),0])
	_move(sim, [-48,0])

func _to_lens(sim: RefCounted) -> void:
	_to_court(sim)
	_move(sim, [-48,-356])
	_move(sim, [40,-356])

func _return_lens(sim: RefCounted) -> void:
	_move(sim, [-48,-356])
	_move(sim, [-48,60])
	_move(sim, [40,60])
	sim.step({"interact": true})
	while not sim.finished:
		sim.step({})

func _move(sim: RefCounted, destination: Array) -> void:
	for _i in range(200):
		if sim.finished:
			return
		var state: Dictionary = sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		# Inherited positions can differ by half an eight-centimetre step. Stop
		# at the nearest reachable grid point rather than oscillating across it.
		if absi(dx) <= 4 and absi(dz) <= 4:
			return
		sim.step({"move_x": signi(dx) if absi(dx) > 4 else 0, "move_z": 0 if absi(dx) > 4 else signi(dz)})

func _bare(player: Dictionary) -> Dictionary:
	return {"x": player.x, "z": player.z, "surface_id": player.surface_id}

func _rehash(record: Dictionary) -> void:
	record.recording_hash = Simulation.recording_hash(record)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
