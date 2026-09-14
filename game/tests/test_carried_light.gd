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
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-four-v3.json"))
	if not fixture is Dictionary or not fixture.get("pairs") is Array or fixture.pairs.size() != 4 or not fixture.get("checkpoints") is Array or fixture.checkpoints.size() != 5:
		_check(false,"The preserved first-four-stage fixture is complete")
		_finish()
		return
	pairs = fixture.pairs
	checkpoints = fixture.checkpoints
	_test_earlier_records()
	_test_removal_and_reservation()
	_test_exact_release_and_fit()
	_test_resume_across_authority_changes()
	_test_wrong_targets_and_deadline()
	_test_proof_and_negative_inputs()
	_test_alternate_endpoint()
	_check(checks >= 50 and not second.is_empty(),"All physical, transfer, resume and negative test groups ran")
	_finish()

func _finish() -> void:
	print("AFTER YOU CARRIED LIGHT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_earlier_records() -> void:
	var prefix: Array = []
	_check(Canonical.same(Simulation.initial_checkpoint(),checkpoints[0]),"The original initial checkpoint is unchanged")
	for index in range(4):
		var pair: Dictionary = pairs[index]
		for role: String in ["a","b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			_check(Simulation.verify_recording(pair[role],prior,prefix).valid,"An exact earlier frozen record verifies with the transfer-capable engine")
			var replay := Simulation.new()
			replay.reset(role,prior,prefix)
			for input: Dictionary in Simulation.expand_recording_inputs(pair[role]):
				replay.step(input)
			_check(Canonical.same(replay.export_recording(),pair[role]),"Every earlier recorded action, integrity check and full hash remains exact")
		prefix.append(pair)
		var cp := Simulation.checkpoint_from_pairs(prefix)
		_check(cp.valid and Canonical.same(cp.checkpoint,checkpoints[index+1]),"The derived earlier checkpoint is unchanged")

func _test_removal_and_reservation() -> void:
	var a := Simulation.new()
	_check(a.reset("a",{},pairs),"The fifth stage loads from the full four-pair proof")
	var initial := a.snapshot()
	_check(initial.stage_id == "what-carried-you" and initial.active_slot == "p0" and initial.first_player_slot == "p0","The next first role alternates back to p0")
	_check(Canonical.same(_bare(initial.players.p0),checkpoints[4].players.p0) and Canonical.same(_bare(initial.players.p1),checkpoints[4].players.p1),"Both players keep their actual timed-route endpoints")
	_check(initial.handoff.authority == "source" and Canonical.same(initial.props,checkpoints[4].mechanisms.props),"The existing fitted prop begins reserved to the source, not duplicated or respawned")
	_check(initial.optics.signals["remembered-north"] and a.walkable_at(192,0) and a.walkable_at(392,0),"The old Court light shines while both new crossings are already physically remembered")
	a.step({"interact":true})
	_check(a.snapshot().props["portable-lens"].status == "fitted" and not a.can_commit(),"A distant action cannot take the Court lens")
	_to_cradle(a)
	_check(a.snapshot().context_action.id == "take","The actual Court socket exposes the pickup")
	a.step({"interact":true})
	var carried := a.snapshot()
	_check(carried.props["portable-lens"].status == "carried" and carried.props["portable-lens"].holder_slot == "p0" and carried.props["portable-lens"].socket_id == "","Taking the fitted lens clears its old socket and records exactly one source holder")
	_check(not carried.optics.signals["remembered-north"] and a.walkable_at(-350,0) and a.walkable_at(-48,-180) and a.walkable_at(-48,180) and a.walkable_at(192,0) and a.walkable_at(392,0),"Removing the working lens darkens the optical apparatus without breaking any earned crossing")
	_to_perch(a)
	_check(a.snapshot().players.p0.surface_id == "rest-rock" and a.snapshot().context_action.id == "offer" and not a.can_commit(),"A real carry reaches the distinct transfer perch, but an unoffered lens is not a valid source")
	a.step({"interact":true})
	var offered := a.snapshot()
	_check(a.can_commit() and not a.complete and offered.handoff.release_tick == a.tick,"The grounded offer immediately becomes a viable source without a hold timer")
	_check(offered.props["portable-lens"].status == "offered" and offered.props["portable-lens"].socket_id == "rest-perch" and offered.handoff.release_state_hash == Canonical.digest(offered.props["portable-lens"]),"Release binds the exact placed prop, socket and tick")
	a.step({})
	a.step({"interact":true})
	_check(a.snapshot().props["portable-lens"].status == "offered" and a.snapshot().context_action.id == "none","The source cannot take its offer back and invalidate the later player")
	var source := Simulation.new()
	source.reset("a",{},pairs)
	for _i in range(60):
		source.step({})
	_to_cradle(source)
	source.step({"interact":true})
	_to_perch(source)
	source.step({"interact":true})
	var b := Simulation.new()
	b.reset("b",source.export_recording(),pairs)
	_to_cradle(b)
	_check(b.snapshot().handoff.authority == "source" and b.snapshot().context_action.id == "reserved","B cannot steal the fitted source-owned lens before its recording picks it up")
	b.step({"interact":true})
	_check(b.snapshot().props["portable-lens"].holder_slot != "p1" and b.snapshot().handoff.claim_tick == -1,"Pressing Take before release cannot assign the prop to B")
	while b.tick < 145:
		b.step({})
	var tracked := b.snapshot()
	_check(tracked.props["portable-lens"].status == "carried" and tracked.props["portable-lens"].holder_slot == "p0" and tracked.props["portable-lens"].x == tracked.players.p0.x and tracked.props["portable-lens"].z == tracked.players.p0.z,"Before release, the one canonical prop follows the independently replayed source's real carry")

func _test_exact_release_and_fit() -> void:
	var a := _source()
	first = a.export_recording()
	var b := Simulation.new()
	b.reset("b",first,pairs)
	_to_perch(b)
	var release: int = a.snapshot().handoff.release_tick
	_check(b.tick < release and b.snapshot().handoff.authority == "source","B can arrive at the safe perch before the actual offer without seeing it early")
	while b.tick < release-1:
		b.step({})
	b.step({"interact":true})
	var claimed := b.snapshot()
	_check(claimed.handoff.release_tick == release and claimed.handoff.claim_tick == release and claimed.handoff.authority == "receiver","A queued interaction can claim on the exact release tick, after source playback but never before it")
	_check(claimed.props["portable-lens"].status == "carried" and claimed.props["portable-lens"].holder_slot == "p1" and claimed.props["portable-lens"].socket_id == "","The released object becomes B's sole carried prop with no stale socket")
	for _i in range(4):
		b.step({"interact":true})
	_check(b.snapshot().handoff.claim_tick == release and b.snapshot().props.size() == 1,"A held button cannot duplicate or re-claim the lens")
	_to_projector(b)
	_check(b.snapshot().context_action.id == "fit" and b.snapshot().context_action.label == "Fit projector","The physically reached receiver-owned projector accepts the same carried lens")
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	second = b.export_recording()
	_check(b.complete and Simulation.verify_recording(second,first,pairs).valid,"Actual removal, source carry, release, receiver carry and fit produce a verified completed pair")
	_check(Canonical.same(_bare(b.snapshot().players.p0),_bare(a.snapshot().players.p0)) and b.snapshot().props["portable-lens"].socket_id == "tower-projector","The final source pose stays exact while B's fitted prop state takes precedence")

func _test_resume_across_authority_changes() -> void:
	var a := _source(-1,180)
	var source: Dictionary = a.export_recording()
	var b := Simulation.new()
	b.reset("b",source,pairs)
	_to_perch(b)
	var drafts: Array = [b.export_recording()]
	while b.tick < int(a.snapshot().handoff.release_tick):
		b.step({})
	drafts.append(b.export_recording())
	b.step({"interact":true})
	drafts.append(b.export_recording())
	_move(b,[288,0])
	_move(b,[392,0])
	drafts.append(b.export_recording())
	_check(b.snapshot().players.p1.surface_id == "rest-tower" and b.snapshot().props["portable-lens"].surface_id == "rest-tower","The receiver's prop follows its exact bridge surface while source playback continues")
	_move(b,[650,0])
	b.step({"interact":true})
	drafts.append(b.export_recording())
	_check(b.snapshot().objective_done and not b.finished and b.snapshot().props["portable-lens"].status == "fitted","The projector can be filled before a deliberately longer source recording ends")
	var fitted: Dictionary = b.snapshot().props.duplicate(true)
	for _i in range(30):
		b.step({})
	_check(Canonical.same(b.snapshot().props,fitted) and b.snapshot().handoff.authority == "receiver","Later source frames never overwrite or respawn a lens already fitted by B")
	while not b.finished:
		b.step({})
	var final_record := b.export_recording()
	for draft: Dictionary in drafts:
		var restored := Simulation.new()
		_check(restored.resume_recording(JSON.parse_string(JSON.stringify(draft)),source,pairs) and restored.snapshot().events.is_empty(),"Every authority-boundary draft resumes through full proof without presentation events")
		var frames := Simulation.expand_recording_inputs(final_record)
		for index in range(int(draft.duration_ticks),frames.size()):
			restored.step(frames[index])
		_check(restored.complete and Canonical.same(restored.export_recording(),final_record),"The same remaining controls preserve the exact final transfer and recording after resume")

func _test_wrong_targets_and_deadline() -> void:
	var a := Simulation.new()
	a.reset("a",{},pairs)
	_to_cradle(a)
	a.step({"interact":true})
	_to_projector(a)
	a.step({"interact":true})
	_check(not a.can_commit() and not a.snapshot().objective_done and a.snapshot().props["portable-lens"].holder_slot == "p0","A cannot skip the handoff and fit B's projector by itself")
	var probe := _source()
	var deadline: int = Simulation.MAX_TICKS-probe.source_budget_ticks()
	var last := _source(deadline)
	_check(last.can_commit() and last.snapshot().handoff.release_tick == deadline,"An offer at the conservative final release tick is still viable")
	var b := Simulation.new()
	b.reset("b",last.export_recording(),pairs)
	while b.tick < deadline:
		b.step({})
	_to_perch(b)
	b.step({"interact":true})
	_to_projector(b)
	b.step({"interact":true})
	_check(b.complete and b.tick <= Simulation.MAX_TICKS,"The receiver can wait until that release and still physically reach, claim and fit the lens")
	var late := _source(deadline+1)
	_check(not late.can_commit() and "earlier" in late.commit_reason() and not Simulation.new().reset("b",late.export_recording(),pairs),"One tick beyond the conservative offer deadline is held instead of accepting an impossible dependency")

func _test_proof_and_negative_inputs() -> void:
	var before := Canonical.digest(pairs)
	var full := pairs+[ {"a":first,"b":second} ]
	var cp := Simulation.checkpoint_from_pairs(full)
	_check(cp.valid and cp.checkpoint.stage_index == 5 and cp.checkpoint.mechanisms.flags["projector-loaded"],"Only the completed verified transfer derives the projector checkpoint")
	_check(cp.checkpoint.mechanisms.props["portable-lens"].status == "fitted" and cp.checkpoint.mechanisms.props["portable-lens"].socket_id == "tower-projector" and cp.checkpoint.mechanisms.props["portable-lens"].holder_slot == "","The checkpoint stores the actual terminal receiver-owned fit")
	_check(cp.checkpoint.mechanisms.latched_bridges == checkpoints[4].mechanisms.latched_bridges and Canonical.digest(pairs) == before,"Moving the lens preserves every remembered path and immutable earlier pair")
	var next := Simulation.new()
	_check(next.reset("a",{},full) and next.snapshot().stage_id == "a-welcome-left-on" and next.snapshot().props["portable-lens"].socket_id == "tower-projector","The verified transfer starts the final stage with the actual fitted projector lens")
	var bad := first.duplicate(true)
	bad["release_tick"] = 1
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,{},pairs).valid,"A caller-supplied release event is rejected rather than replacing source execution")
	bad = first.duplicate(true)
	bad.actions[-1].action = false
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,{},pairs).valid,"Removing the actual source placement cannot keep its original release state/hash")
	bad = second.duplicate(true)
	bad.source_recording_hash = "9".repeat(64)
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,first,pairs).valid,"B cannot attach a claimed prop to an unrelated source")
	bad = second.duplicate(true)
	bad.checkpoint_hash = checkpoints[3].checkpoint_hash
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(bad,first,pairs).valid,"An older checkpoint cannot invent already remembered eastern paths")
	var restored := Simulation.new()
	restored.reset("b",first,pairs)
	restored.step({})
	_check(not restored.resume_recording(bad,first,pairs) and restored.export_recording().is_empty(),"An invalid transfer resume cannot leave a previously loaded engine active")
	_check(not Simulation.new().reset("a",{},[checkpoints[4]]),"A self-hashed checkpoint is never accepted as lens ownership evidence")
	var invalid := Simulation.new()
	invalid.reset("b",first,pairs)
	invalid.step({"claim_tick":1})
	_check(invalid.tick == 0 and invalid.export_recording().is_empty(),"Unsupported inputs cannot force a release or claim")

func _test_alternate_endpoint() -> void:
	# Extend the valid stage-four source on permanent floor, then let its B
	# leave the tower after ringing the bell while that source finishes.
	var prefix := pairs.slice(0,3)
	var source := Simulation.new()
	source.resume_recording(pairs[3].a,{},prefix)
	while source.tick < 400:
		source.step({})
	var receiver := Simulation.new()
	receiver.reset("b",source.export_recording(),prefix)
	for frame: Dictionary in Simulation.expand_recording_inputs(pairs[3].b):
		receiver.step(frame)
	_move(receiver,[-48,0])
	_move(receiver,[-48,-352])
	while not receiver.finished:
		receiver.step({})
	var alternative := prefix+[ {"a":source.export_recording(),"b":receiver.export_recording()} ]
	var cp := Simulation.checkpoint_from_pairs(alternative)
	_check(cp.valid and cp.checkpoint.players.p0.surface_id == "north","A valid timed-route receiver can leave a genuine North endpoint before its source ends")
	var a := _source(-1,0,alternative)
	var b := Simulation.new()
	b.reset("b",a.export_recording(),alternative)
	_check(Canonical.same(_bare(b.snapshot().players.p0),cp.checkpoint.players.p0),"The next source starts at that exact endpoint, without a tower spawn assumption")
	_to_perch(b)
	while b.snapshot().handoff.authority == "source" and not b.finished:
		b.step({})
	b.step({"interact":true})
	_to_projector(b)
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	_check(b.complete and Simulation.verify_recording(b.export_recording(),a.export_recording(),alternative).valid,"The full transfer also succeeds when its source must return from North")

func _source(release_tick: int = -1, after_release_ticks: int = 0, evidence: Array = []) -> RefCounted:
	var a := Simulation.new()
	a.reset("a",{},pairs if evidence.is_empty() else evidence)
	_to_cradle(a)
	a.step({"interact":true})
	_to_perch(a)
	while a.tick < release_tick-1 and not a.finished:
		a.step({})
	a.step({"interact":true})
	for _i in range(after_release_ticks):
		a.step({})
	return a

func _to_line(sim: RefCounted) -> void:
	var p: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
	if p.surface_id in ["north","court-north","south","court-south"]:
		_move(sim,[-48,int(p.z)])
		_move(sim,[-48,0])
	else:
		_move(sim,[int(p.x),0])

func _to_cradle(sim: RefCounted) -> void:
	_to_line(sim)
	_move(sim,[40,0])
	_move(sim,[40,60])

func _to_perch(sim: RefCounted) -> void:
	_to_line(sim)
	_move(sim,[288,0])
	_move(sim,[288,64])

func _to_projector(sim: RefCounted) -> void:
	_to_line(sim)
	_move(sim,[650,0])

func _move(sim: RefCounted, destination: Array) -> void:
	for _i in range(220):
		if sim.finished:
			return
		var p: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
		var dx := int(destination[0])-int(p.x)
		var dz := int(destination[1])-int(p.z)
		if absi(dx)<=4 and absi(dz)<=4:
			return
		sim.step({"move_x":signi(dx) if absi(dx)>4 else 0,"move_z":0 if absi(dx)>4 else signi(dz)})

func _bare(p: Dictionary) -> Dictionary:
	return {"x":p.x,"z":p.z,"surface_id":p.surface_id}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
