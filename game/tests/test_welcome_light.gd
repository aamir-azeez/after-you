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
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-five-v3.json"))
	if not fixture is Dictionary or not fixture.get("pairs") is Array or fixture.pairs.size() != 5 or not fixture.get("checkpoints") is Array or fixture.checkpoints.size() != 6:
		_check(false,"The preserved first-five-stage fixture is complete")
		_finish()
		return
	pairs = fixture.pairs
	checkpoints = fixture.checkpoints
	_test_exact_prefix()
	_test_pad_and_mirror()
	_test_real_combined_activation()
	_test_source_ownership()
	_test_interruption_and_deadline()
	_test_resume_and_final_proof()
	_test_alternate_endpoints()
	_check(checks >= 60 and not second.is_empty(),"All final-beacon groups executed with actual controls")
	_finish()

func _finish() -> void:
	print("AFTER YOU WELCOME LIGHT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_exact_prefix() -> void:
	var prefix: Array = []
	_check(Canonical.same(Simulation.initial_checkpoint(),checkpoints[0]),"The chapter's original initial checkpoint stays exact")
	for index in range(5):
		var pair: Dictionary = pairs[index]
		for role: String in ["a","b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			_check(Simulation.verify_recording(pair[role],prior,prefix).valid,"The final engine verifies each earlier frozen recording")
			var replay := Simulation.new()
			replay.reset(role,prior,prefix)
			for input: Dictionary in Simulation.expand_recording_inputs(pair[role]):
				replay.step(input)
			_check(Canonical.same(replay.export_recording(),pair[role]),"Every earlier action, integrity checkpoint and recording hash remains unchanged")
		prefix.append(pair)
		var derived := Simulation.checkpoint_from_pairs(prefix)
		_check(derived.valid and Canonical.same(derived.checkpoint,checkpoints[index+1]),"Each earlier derived chapter checkpoint remains exact")

func _test_pad_and_mirror() -> void:
	var a := Simulation.new()
	_check(a.reset("a",{},pairs),"The final stage loads only after the five complete pairs")
	var start := a.snapshot()
	_check(start.stage_id == "a-welcome-left-on" and start.active_slot == "p1" and start.first_player_slot == "p1","The final source role alternates to the receiver who fitted the projector")
	_check(Canonical.same(_bare(start.players.p0),checkpoints[5].players.p0) and Canonical.same(_bare(start.players.p1),checkpoints[5].players.p1),"The final stage inherits both exact physical endpoints")
	_check(Canonical.same(start.props,checkpoints[5].mechanisms.props) and start.props["portable-lens"].socket_id == "tower-projector","The projector uses the actual transferred lens without respawning or taking it")
	_check(not start.beacon.ready and not start.beacon.lit and not start.hold_pads["beacon-hold"],"An installed lens alone does not turn the final beacon on")
	_to_upper(a)
	a.step({"interact":true})
	_check(a.snapshot().mirrors["beacon-upper-mirror"] == "slash" and not a.snapshot().optics.signals["beacon-upper"] and not a.can_commit(),"Correct mirror alignment without the occupied source pad is insufficient")
	_move(a,[648,-80])
	a.step({"move_x":1})
	var held := a.snapshot()
	_check(held.hold_pads["beacon-hold"] and held.optics.signals["beacon-upper"] and held.hold_ticks == 1 and a.can_commit(),"The first physically held, correctly routed source tick is viable without an added wait timer")
	_check(not held.beacon.signals["beacon-lower"] and not held.objective_done,"A single lit branch cannot auto-complete the finale")
	var wrong := Simulation.new()
	wrong.reset("a",{},pairs)
	_to_upper(wrong)
	_move(wrong,[680,-80])
	_check(wrong.snapshot().hold_pads["beacon-hold"] and not wrong.snapshot().beacon.signals["beacon-upper"] and not wrong.can_commit(),"Standing on the pad with the wrong mirror diagonal does not create a valid source")

func _test_real_combined_activation() -> void:
	var a := _source()
	first = a.export_recording()
	var b := Simulation.new()
	b.reset("b",first,pairs)
	b.step({"interact":true})
	_check(not b.snapshot().objective_done,"Pressing Action at the inherited distant endpoint cannot activate the beacon")
	_to_lower(b)
	_check(b.snapshot().context_action.id == "rotate" and b.snapshot().beacon.signals["beacon-upper"],"The receiver reaches its own mirror while the immutable source holds the other branch")
	_move(b,[716,80])
	_check(b.snapshot().context_action.id == "light_beacon" and not b.snapshot().context_action.enabled,"The actual crest refuses activation while its lower branch is unaligned")
	b.step({"interact":true})
	_check(not b.complete and not b.snapshot().objective_done,"An incomplete two-light pattern cannot be committed by pressing the final action")
	_move(b,[668,80])
	b.step({"interact":true})
	_check(b.snapshot().beacon.ready and not b.snapshot().beacon.lit and not b.complete,"Both true receiver signals still require a deliberate grounded final action")
	_move(b,[700,40])
	b.step({"interact":true})
	_check(b.snapshot().context_action.id == "none" and not b.snapshot().objective_done,"Being near the apparatus but outside the actual crest cannot substitute for standing on it")
	_move(b,[716,80])
	_check(b.snapshot().beacon.crest_occupied and b.snapshot().context_action.enabled,"The real crest exposes the final action once both paths shine")
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	second = b.export_recording()
	_check(b.complete and b.snapshot().beacon.lit and b.can_commit() and Simulation.verify_recording(second,first,pairs).valid,"Two physical contributions and an explicit crest action complete the verified final pair")
	_check(Canonical.same(_bare(b.snapshot().players.p1),_bare(a.snapshot().players.p1)) and Canonical.same(b.snapshot().props,checkpoints[5].mechanisms.props),"Completion preserves the source pose and exact fitted lens")
	var immutable := Canonical.digest(second)
	b.step({"interact":true})
	_check(Canonical.digest(b.export_recording()) == immutable,"Input after completed final activation cannot duplicate or alter the committed turn")

func _test_source_ownership() -> void:
	var delayed := _source(180)
	var b := Simulation.new()
	b.reset("b",delayed.export_recording(),pairs)
	_to_upper(b)
	_check(b.tick < 180 and b.snapshot().context_action.id == "reserved","The later player cannot rotate the source-owned upper mirror")
	var orientation: String = b.snapshot().mirrors["beacon-upper-mirror"]
	b.step({"interact":true})
	_check(b.snapshot().mirrors["beacon-upper-mirror"] == orientation,"A reserved-control action cannot rewrite an earlier mirror recording")
	_move(b,[680,-80])
	_check(b.tick < 180 and not b.snapshot().hold_pads["beacon-hold"] and not b.snapshot().beacon.signals["beacon-upper"],"The receiver standing on the other player's pad cannot power that source early")
	while b.tick < 180:
		b.step({})
	var source_pose: Dictionary = b.snapshot().players.p1.duplicate(true)
	_move(b,[int(source_pose.x),int(source_pose.z)])
	var overlap: Dictionary = b.snapshot().players.p0
	var separation := Vector2i(int(overlap.x)-int(source_pose.x),int(overlap.z)-int(source_pose.z))
	_check(separation.length_squared() < 4*Simulation.RADIUS*Simulation.RADIUS and overlap.surface_id == source_pose.surface_id and Canonical.same(b.snapshot().players.p1,source_pose) and b.snapshot().hold_pads["beacon-hold"],"The later player's physical footprint can overlap the recorded pad holder without moving or blocking its ghost")
	_to_lower(b)
	b.step({"interact":true})
	_check(b.snapshot().beacon.signals["beacon-upper"] and b.snapshot().beacon.signals["beacon-lower"] and Canonical.same(b.snapshot().players.p1,source_pose),"The receiver's independent lower mirror cannot extinguish or move the upper source")
	b.step({})
	b.step({"interact":true})
	_check(not b.snapshot().beacon.signals["beacon-lower"] and b.snapshot().beacon.signals["beacon-upper"],"Turning the lower mirror away affects only its own optical path")
	var a := _source()
	_move(a,[716,80])
	_check(a.snapshot().context_action.id == "reserved" and not a.snapshot().context_action.enabled,"The source cannot use the receiver's final crest")

func _test_interruption_and_deadline() -> void:
	var interrupted := _source()
	_move(interrupted,[720,-80])
	_move(interrupted,[680,-80])
	_check(interrupted.snapshot().beacon.signals["beacon-upper"] and not interrupted.can_commit() and "interrupted" in interrupted.commit_reason(),"Leaving and returning to the source pad cannot repair its broken continuous contribution")
	_check(not Simulation.new().reset("b",interrupted.export_recording(),pairs),"A broken source cannot become the next player's dependency")
	var probe := _source()
	var latest: int = Simulation.MAX_TICKS-probe.source_budget_ticks()
	var last := _source(latest)
	_check(last.can_commit() and last.snapshot().first_power_tick == latest and last.snapshot().hold_ticks == 1,"The last conservative first-light tick remains an immediately usable source")
	var b := Simulation.new()
	b.reset("b",last.export_recording(),pairs)
	while b.tick < latest:
		b.step({})
	_to_lower(b)
	b.step({"interact":true})
	_move(b,[716,80])
	b.step({"interact":true})
	_check(b.complete and b.tick <= Simulation.MAX_TICKS,"The receiver can wait for the last valid light then walk, align and activate within the turn limit")
	var late := _source(latest+1)
	_check(not late.can_commit() and "earlier" in late.commit_reason() and not Simulation.new().reset("b",late.export_recording(),pairs),"One tick too late is held instead of creating an impossible final dependency")

func _test_resume_and_final_proof() -> void:
	var source := _source(-1,220)
	var a_record: Dictionary = source.export_recording()
	var b := Simulation.new()
	b.reset("b",a_record,pairs)
	_to_lower(b)
	var drafts: Array = [b.export_recording()]
	b.step({"interact":true})
	drafts.append(b.export_recording())
	_move(b,[716,80])
	b.step({"interact":true})
	drafts.append(b.export_recording())
	_check(b.snapshot().beacon.lit and not b.finished,"The final activation can occur before a longer valid source finishes")
	while not b.finished:
		b.step({})
	var final_record := b.export_recording()
	for draft: Dictionary in drafts:
		var resumed := Simulation.new()
		_check(resumed.resume_recording(JSON.parse_string(JSON.stringify(draft)),a_record,pairs) and resumed.snapshot().events.is_empty(),"A draft before alignment, before activation or after activation resumes silently from full evidence")
		var inputs := Simulation.expand_recording_inputs(final_record)
		for index in range(int(draft.duration_ticks),inputs.size()):
			resumed.step(inputs[index])
		_check(resumed.complete and Canonical.same(resumed.export_recording(),final_record),"The same remaining input produces the exact final recording after resume")
	var full := pairs+[{"a":first,"b":second}]
	var done := Simulation.checkpoint_from_pairs(full)
	_check(done.valid and done.checkpoint.stage_index == 6 and done.checkpoint.mechanisms.flags["beacon-lit"],"Exactly six completed verified pairs derive the final beacon checkpoint")
	_check(done.checkpoint.mechanisms.latched_bridges == checkpoints[5].mechanisms.latched_bridges and Canonical.same(done.checkpoint.mechanisms.props,checkpoints[5].mechanisms.props),"Final activation retains the chapter's real remembered paths and transferred prop")
	_check(not Simulation.new().reset("a",{},full) and not Simulation.checkpoint_from_pairs(full+[{"a":first,"b":second}]).valid,"A complete chapter has no fabricated seventh stage or duplicate final pair")
	var removed := second.duplicate(true)
	removed.actions[-1].action = false
	removed.recording_hash = Simulation.recording_hash(removed)
	_check(not Simulation.verify_recording(removed,first,pairs).valid,"Deleting the actual crest action cannot preserve the completion and hash")
	var forged := first.duplicate(true)
	forged["pad_occupied"] = true
	forged.recording_hash = Simulation.recording_hash(forged)
	_check(not Simulation.verify_recording(forged,{},pairs).valid,"A caller-supplied occupied pad is not a substitute for actual player controls")
	forged = second.duplicate(true)
	forged.source_recording_hash = "3".repeat(64)
	forged.recording_hash = Simulation.recording_hash(forged)
	_check(not Simulation.verify_recording(forged,first,pairs).valid,"The final pair binds its exact earlier light recording")
	forged = second.duplicate(true)
	forged.checkpoint_hash = checkpoints[4].checkpoint_hash
	forged.recording_hash = Simulation.recording_hash(forged)
	var resumed := Simulation.new()
	resumed.reset("b",first,pairs)
	_check(not resumed.resume_recording(forged,first,pairs) and resumed.export_recording().is_empty(),"A stale projector checkpoint cannot resume or leave a previous live engine loaded")
	var changed := pairs.duplicate(true)
	changed[4].b.completed = false
	changed[4].b.recording_hash = Simulation.recording_hash(changed[4].b)
	_check(not Simulation.new().reset("a",{},changed) and not Simulation.new().reset("a",{},[checkpoints[5]]),"A fake fitted-lens history or standalone checkpoint cannot unlock the beacon stage")
	var invalid := Simulation.new()
	invalid.reset("b",first,pairs)
	invalid.step({"beacon_lit":true})
	_check(invalid.tick == 0 and invalid.export_recording().is_empty(),"Unsupported input cannot assert a final beacon state")

func _test_alternate_endpoints() -> void:
	# The prior source can walk after its real release, and B can walk after
	# fitting the projector while that source is still playing. Retain both.
	var prefix := pairs.slice(0,4)
	var source := Simulation.new()
	source.resume_recording(pairs[4].a,{},prefix)
	_to_line(source)
	_move(source,[-48,0])
	_move(source,[-48,-352])
	while source.tick < 450:
		source.step({})
	var receiver := Simulation.new()
	receiver.reset("b",source.export_recording(),prefix)
	for input: Dictionary in Simulation.expand_recording_inputs(pairs[4].b):
		receiver.step(input)
	_to_line(receiver)
	_move(receiver,[-728,0])
	while not receiver.finished:
		receiver.step({})
	var alternate := prefix+[{"a":source.export_recording(),"b":receiver.export_recording()}]
	var cp := Simulation.checkpoint_from_pairs(alternate)
	_check(cp.valid and cp.checkpoint.players.p0.surface_id == "north" and cp.checkpoint.players.p1.surface_id == "harbour","A legitimate transfer can leave the next two players at North and Harbour")
	var a := _source(-1,0,alternate)
	var b := Simulation.new()
	b.reset("b",a.export_recording(),alternate)
	_check(Canonical.same(_bare(b.snapshot().players.p0),cp.checkpoint.players.p0),"The final receiver begins at its exact North endpoint rather than a reset spawn")
	_to_lower(b)
	b.step({"interact":true})
	_move(b,[716,80])
	while not b.snapshot().beacon.ready and not b.finished:
		b.step({})
	b.step({"interact":true})
	while not b.finished:
		b.step({})
	_check(b.complete and Simulation.verify_recording(b.export_recording(),a.export_recording(),alternate).valid,"Actual final-beacon controls also succeed after both inherited endpoints change")

func _source(power_tick: int = -1, tail: int = 0, evidence: Array = []) -> RefCounted:
	var a := Simulation.new()
	a.reset("a",{},pairs if evidence.is_empty() else evidence)
	_to_upper(a)
	a.step({"interact":true})
	_move(a,[648,-80])
	while a.tick < power_tick-1 and not a.finished:
		a.step({})
	a.step({"move_x":1})
	for _i in range(tail):
		a.step({})
	return a

func _to_line(sim: RefCounted) -> void:
	var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
	if player.surface_id in ["north","court-north","south","court-south"]:
		_move(sim,[-48,int(player.z)])
		_move(sim,[-48,0])
	else:
		_move(sim,[int(player.x),0])

func _to_upper(sim: RefCounted) -> void:
	_to_line(sim)
	_move(sim,[632,0])
	_move(sim,[632,-80])

func _to_lower(sim: RefCounted) -> void:
	_to_line(sim)
	_move(sim,[668,0])
	_move(sim,[668,80])

func _move(sim: RefCounted, destination: Array) -> void:
	for _i in range(250):
		if sim.finished:
			return
		var player: Dictionary = sim.snapshot().players[sim.snapshot().active_slot]
		var dx := int(destination[0])-int(player.x)
		var dz := int(destination[1])-int(player.z)
		if absi(dx)<=4 and absi(dz)<=4:
			return
		sim.step({"move_x":signi(dx) if absi(dx)>4 else 0,"move_z":0 if absi(dx)>4 else signi(dz)})

func _bare(player: Dictionary) -> Dictionary:
	return {"x":player.x,"z":player.z,"surface_id":player.surface_id}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
