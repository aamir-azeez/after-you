extends SceneTree
## The Wishing Well: route witnesses with real inputs through the native rules.
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Well = preload("res://core/cooperative/wishing_well_catalog.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Witness = preload("res://tests/wishing_well_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const PIT := [1120,-48,1200,48]
const LIP := [1104,-64,1216,-16]
const MOUTH := [1132,-36,1188,-28]
const RADIUS := 12
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var evidence := Witness.chapter()
	_check(evidence.error.is_empty(), "Wishing Well walkthrough uses real controls: " + evidence.error)
	if evidence.error.is_empty():
		_preservation(evidence)
		_pairs(evidence)
		_comfort_alias(evidence)
		_drop_lands_in_pit(evidence)
		_pit_confinement(evidence)
		_pit_inside_pad(evidence)
		_partner_never_reaches_lip(evidence)
		_ladder_meets_tower(evidence)
		_source_cannot_commit_early(evidence)
		_receiver_never_stranded(evidence)
		_long_receiver(evidence)
		_rope_walk_holds_under_ghost(evidence)
		if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args(): _write_fixtures(evidence)
	print("AFTER YOU WISHING WELL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _preservation(evidence: Dictionary) -> void:
	_check(Canonical.digest(Catalog.definition("high-and-low")) == "6aa907e802c92445745a6452c6ec0850dd8e98724e689b58a8ec82915fb08956", "Published free chapter definition remains unchanged")
	_check(Canonical.digest(Catalog.definition("rolling-home")) == "d6aaa6006597dd5e4ce4dbc641d94c81c2ab17c55bd80b50c6a240e0e91cff87", "Published paid chapter definition remains unchanged")
	_check(Canonical.digest(Catalog.definition("a-house-for-two")) == "b868745e7bc025bb8fe5a49b698b15dfb0d428ea9fe905ce46fa46dd27d79867", "Published house definition remains unchanged")
	var level: Dictionary = evidence.definition
	_check(level.schema_version == 6 and level.simulation_version == 9 and level.stages.size() == 2 and not level.premium, "The well composes the simulation6 schema on comfort rules 9, free to host")
	_check(Canonical.same(level, Catalog.definition("the-wishing-well@1")) and Catalog.known(level), "The catalog knows the pinned definition by key")
	print("Wishing Well definition_hash=%s" % Canonical.digest(level))

func _pairs(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	for index in range(2):
		var pair: Dictionary = evidence.pairs[index]
		var previous: Dictionary = evidence.checkpoints[index]
		var checkpoint: Dictionary = evidence.checkpoints[index + 1]
		_check(pair.a.player_slot == ("p0" if index == 0 else "p1") and pair.b.player_slot != pair.a.player_slot, "Partners exchange who goes first")
		_check(pair.a.duration_ticks <= 650 and pair.b.duration_ticks <= 650, "Both turns keep a wide margin below the 900-tick limit")
		for role: String in ["a", "b"]:
			var record: Dictionary = pair[role]
			_check(record.simulation_version == 9, "Turns record comfort rules 9: " + record.stage_id + "/" + role)
			var prior: Dictionary = pair.a if role == "b" else {}
			_check(Simulation.verify_recording(level, _json(record), _json(previous), _json(prior)).valid, "Recording independently verifies across JSON: " + record.stage_id + "/" + role)
			var replay := Simulation.new()
			_check(replay.reset(level, record.stage_id, previous, prior, role), "Replay begins from the exact accepted checkpoint")
			var frames := Simulation.expand_recording_inputs(record)
			var middle := frames.size() / 2
			for frame: Dictionary in frames.slice(0, middle): replay.step(frame)
			var draft := replay.export_recording()
			var resumed := Simulation.new()
			resumed.reset(level, record.stage_id, previous, prior, role)
			for frame: Dictionary in Simulation.expand_recording_inputs(draft): resumed.step(frame)
			_check(replay.state_hash() == resumed.state_hash(), "Saved middle-of-turn input reconstructs exact state")
			for frame: Dictionary in frames.slice(middle): resumed.step(frame)
			_check(Canonical.same(resumed.export_recording(), record), "Resumed turn retains exact recording hashes")
			_bound(record, 65536, "recording")
		var derived := Simulation.derive_checkpoint(level, previous, pair.a, pair.b)
		_check(derived.valid and Canonical.same(derived.checkpoint, checkpoint) and Simulation.verify_checkpoint(level, _json(checkpoint)).valid, "Full accepted proof derives and verifies")
		_bound(checkpoint, 229376, "checkpoint")
		_bound({"schema_version": 2, "recording": pair.b, "checkpoint": checkpoint}, 327680, "turn packet")
		var tampered: Dictionary = pair.a.duplicate(true)
		tampered.actions[0].x = -100 if tampered.actions[0].x != -100 else 100
		tampered.recording_hash = Simulation.recording_hash(tampered)
		_check(not Simulation.verify_recording(level, tampered, previous).valid, "Rehashed inputs cannot invent a valid replay outcome")
		print("Wishing Well stage %s: A=%d ticks (%.1f s) B=%d ticks (%.1f s)" % [level.stages[index].id, pair.a.duration_ticks, pair.a.duration_ticks / 30.0, pair.b.duration_ticks, pair.b.duration_ticks / 30.0])
	var first: Dictionary = evidence.checkpoints[1]
	_check(first.mechanisms.latched_bridges == ["cliff-steps", "long-stair"] and Canonical.same(first.mechanisms.levers, {"garden-gate": true}), "Stage one keeps the steps, the long stair and the gate")
	_check(first.players.p0.surface_id == "well-floor" and _inside_pad(first.players.p0) and first.players.p1.surface_id == "cliff", "The friend who went ahead stays in the well, holding the rope")
	var final: Dictionary = evidence.checkpoints[2]
	_check(final.stage_index == 2 and final.next_stage_id.is_empty(), "Exactly two accepted pairs finish the well")
	_check(final.mechanisms.latched_bridges == ["cliff-steps", "long-stair", "rope-walk-east", "rope-walk-west", "well-ladder"] and Canonical.same(final.mechanisms.levers, {"garden-gate": true, "winch-lever": true}), "Every route and lever of both stages ends latched and on")
	_check(final.players.p0.surface_id == "tower" and final.players.p1.surface_id == "tower", "Both spirits finish together on the tower")
	_check(not Simulation.verify_checkpoint(Catalog.definition("high-and-low"), final).valid, "The well's proof cannot be replayed as another chapter")

func _comfort_alias(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	_check(Registry.supported_rules("the-wishing-well@1") == [9] and Registry.preferred_rules("the-wishing-well@1") == 9, "The registry offers the well only under rules 9")
	_check(Registry.supported_rules(Registry.HIGH_AND_LOW) == [6, 8], "Published chapters keep their rules")
	for rules: int in [6, 8, 10]:
		var refused := Simulation.new()
		_check(not refused.reset(level, "go-on-ahead", evidence.checkpoints[0], {}, "a", rules), "The well refuses rules %d" % rules)
	var high := Catalog.definition("high-and-low")
	var alias := Simulation.new()
	_check(not alias.reset(high, "upper-path", Catalog.initial_checkpoint(high), {}, "a", 9), "Published chapters refuse the rules 9 alias")
	var renumbered: Dictionary = evidence.pairs[0].a.duplicate(true)
	renumbered.simulation_version = 8
	renumbered.recording_hash = Simulation.recording_hash(renumbered)
	_check(not Simulation.verify_recording(level, renumbered, evidence.checkpoints[0]).valid, "A rules 9 turn relabelled as rules 8 does not verify")

func _drop_lands_in_pit(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	# Back approaches across the whole mouth.
	for landing_x: int in [MOUTH[0], 1160, MOUTH[2]]:
		var sim := Witness.source(level, "go-on-ahead", evidence.checkpoints[0], landing_x)
		var p0: Dictionary = sim.snapshot().players.p0
		_check(p0.surface_id == "well-floor" and int(p0.height) == 0 and _inside(p0, PIT, RADIUS) and sim.can_commit(), "Stepping in from the back at x=%d lands inside the pit" % landing_x)
	# Side and diagonal approaches along the lip.
	for approach: Array in [[[1100,-64],[1100,-32],{"move_x": 1.0}], [[1220,-64],[1220,-32],{"move_x": -1.0}], [[1100,-64],[1100,-64],{"move_x": 0.7, "move_z": 0.7}], [[1220,-64],[1220,-64],{"move_x": -0.7, "move_z": 0.7}]]:
		var sim := _on_cliff(level, evidence.checkpoints[0])
		Walk.walk(sim, approach[0]); Walk.walk(sim, approach[1])
		var landed := {}
		for _tick in range(30):
			sim.step(approach[2])
			var p0: Dictionary = sim.snapshot().players.p0
			if p0.surface_id != "cliff":
				landed = p0
				break
		_check(not landed.is_empty() and landed.surface_id == "well-floor" and int(landed.height) == 0 and _inside(landed, PIT, RADIUS) and "drop" in sim.snapshot().events, "Approach %s drops inside the pit" % str(approach[2]))

func _pit_confinement(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var directions := [{"move_x": 1.0}, {"move_x": -1.0}, {"move_z": 1.0}, {"move_z": -1.0}, {"move_x": 0.7, "move_z": 0.7}, {"move_x": -0.7, "move_z": 0.7}, {"move_x": 0.7, "move_z": -0.7}, {"move_x": -0.7, "move_z": -0.7}]
	# Stage one: after the drop, nothing leads out of the pit.
	var sim := Witness.source(level, "go-on-ahead", evidence.checkpoints[0])
	var stayed := true
	for direction: Dictionary in directions:
		for _tick in range(24):
			sim.step(direction)
			var p0: Dictionary = sim.snapshot().players.p0
			stayed = stayed and p0.surface_id == "well-floor" and int(p0.height) == 0 and _inside(p0, PIT, RADIUS)
	_check(stayed and not sim.finished, "In stage one every push stays on the pit floor")
	# Stage two, before the winch: the waiting friend still cannot leave.
	var waiting := Simulation.new()
	waiting.reset(level, "back-for-you", evidence.checkpoints[1], evidence.pairs[1].a, "b")
	stayed = true
	for direction: Dictionary in directions:
		for _tick in range(20):
			if bool(waiting.snapshot().bridges.get("well-ladder", false)): break
			waiting.step(direction)
			var p0: Dictionary = waiting.snapshot().players.p0
			stayed = stayed and p0.surface_id == "well-floor" and _inside(p0, PIT, RADIUS)
	_check(stayed and not bool(waiting.snapshot().bridges.get("well-ladder", false)), "Before the ladder comes down, the friend stays in the pit")
	# Exhaustive: from every pit position, a 1 cm step reaches only the pit or the ladder.
	var closed_exit := false
	var open_exits := {}
	for open: bool in [false, true]:
		var routes := {"cliff-steps": true, "long-stair": true, "rope-walk-west": true, "rope-walk-east": true, "well-ladder": open}
		for slot: String in ["p0", "p1"]:
			for x in range(PIT[0], PIT[2] + 1):
				for z in range(PIT[1], PIT[3] + 1):
					var here := Navigation.at(level, routes, {}, {"height": 0}, x, z, slot, RADIUS)
					if here.is_empty() or here.surface_id != "well-floor": continue
					for step: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
						var next := Navigation.at(level, routes, {}, here, x + step.x, z + step.y, slot, RADIUS)
						if next.is_empty() or next.surface_id == "well-floor": continue
						if open: open_exits[slot + ":" + str(next.surface_id)] = true
						else: closed_exit = true
	_check(not closed_exit, "No pit position has any exit while the ladder is closed")
	_check(open_exits.keys() == ["p0:well-ladder"], "The ladder is the pit's only exit, and only for its owner: " + str(open_exits.keys()))

func _pit_inside_pad(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var pad: Dictionary = level.stages[0].pressure_pads[0]
	var held: Dictionary = level.stages[1].pressure_pads[0]
	_check(Canonical.same(pad.position_cm, held.position_cm) and pad.radius_cm == held.radius_cm and pad.surface_id == held.surface_id and pad.owner_slot == held.owner_slot, "Yesterday's rope and today's held rope are the same place and reach")
	var outside := 0
	var positions := 0
	var farthest := 0.0
	for x in range(PIT[0], PIT[2] + 1):
		for z in range(PIT[1], PIT[3] + 1):
			var here := Navigation.at(level, {}, {}, {"height": 0}, x, z, "p0", RADIUS)
			if here.is_empty() or here.surface_id != "well-floor": continue
			positions += 1
			var distance := Vector2(x - pad.position_cm[0], z - pad.position_cm[1]).length()
			farthest = maxf(farthest, distance)
			if distance > float(pad.radius_cm): outside += 1
	_check(positions > 0 and outside == 0, "Every one of %d pit positions is inside the 48 cm rope pad (farthest %.1f cm)" % [positions, farthest])
	_check(pad.position_cm[1] > LIP[3], "The rope pad's centre is in the open front of the well, not under the lip")
	# Real inputs: walk to every corner of the pit; the rope never lets go.
	var sim := Witness.source(level, "go-on-ahead", evidence.checkpoints[0])
	var always := true
	for corner: Array in [[1132,-36],[1188,-36],[1188,36],[1132,36],[1160,0]]:
		for axis: int in [0, 1]:
			for _tick in range(20):
				var player: Dictionary = sim.snapshot().players.p0
				var delta := int(corner[axis]) - int(player.x if axis == 0 else player.z)
				if absi(delta) <= 1: break
				sim.step({"move_x": clampf(delta / 8.0, -1, 1)} if axis == 0 else {"move_z": clampf(delta / 8.0, -1, 1)})
				always = always and bool(sim.snapshot().hold_pads["bucket-rope"])
	_check(always and sim.can_commit(), "Walking every corner of the pit keeps the rope held")

func _partner_never_reaches_lip(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	# Stage one receiver after climbing, and stage two source from the bell.
	var cases: Array = []
	var climber := Simulation.new()
	climber.reset(level, "go-on-ahead", evidence.checkpoints[0], evidence.pairs[0].a, "b")
	Witness._route(climber, Witness.GARDEN_PATH)
	Witness.wait_for_route(climber, "long-stair")
	Walk.walk(climber, [976,-96])
	cases.append(climber)
	var returning := Simulation.new()
	returning.reset(level, "back-for-you", evidence.checkpoints[1])
	cases.append(returning)
	var missed: Array = []
	for base: RefCounted in cases:
		for approach: Array in [[[1160,-96],{"move_z": 1.0}], [[1088,-40],{"move_x": 1.0}], [[1220,-96],{"move_z": 1.0}], [[1088,-96],{"move_x": 0.7, "move_z": 0.7}], [[1220,-96],{"move_x": -0.7, "move_z": 0.7}]]:
			var sim: RefCounted = _clone_turn(level, base)
			Walk.walk(sim, approach[0])
			var start: Dictionary = sim.snapshot().players.p1
			if sim.finished or absi(int(start.x) - int(approach[0][0])) > 1 or absi(int(start.z) - int(approach[0][1])) > 1:
				missed.append("%s start %d,%d" % [str(approach[0]), int(start.x), int(start.z)])
			for _tick in range(40):
				sim.step(approach[1])
				var p1: Dictionary = sim.snapshot().players.p1
				# Sliding along the lip onto the partner's own stair is fine; the pit and lip never are.
				if p1.surface_id == "well-floor" or "drop" in sim.snapshot().events or _circle_touches(p1, LIP):
					missed.append("%s reached %s %d,%d" % [str(approach[1]), str(p1.surface_id), int(p1.x), int(p1.z)])
					break
	_check(missed.is_empty(), "The partner can never step onto the lip or fall into the well: " + str(missed))

func _ladder_meets_tower(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var sim := Simulation.new()
	sim.reset(level, "back-for-you", evidence.checkpoints[1], evidence.pairs[1].a, "b")
	Witness.wait_for_route(sim, "well-ladder")
	Walk.walk(sim, [1180,16])
	var last_height := -1
	var rising := true
	for _tick in range(80):
		sim.step({"move_x": 1.0})
		var p0: Dictionary = sim.snapshot().players.p0
		rising = rising and int(p0.height) >= last_height
		last_height = int(p0.height)
		if p0.surface_id == "tower": break
	var top: Dictionary = sim.snapshot().players.p0
	_check(rising and top.surface_id == "tower" and int(top.height) == 160 and int(top.x) >= 1568, "Climbing the ladder rises steadily and steps straight onto the tower")

func _source_cannot_commit_early(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var garden := Simulation.new()
	garden.reset(level, "go-on-ahead", evidence.checkpoints[0])
	Walk.walk(garden, [-1104,200]); Walk.tap(garden); Walk.wait_ticks(garden, 20)
	_check(not garden.can_commit() and bool(garden.snapshot().bridges["cliff-steps"]) and not bool(garden.snapshot().bridges["long-stair"]), "The gate alone cannot be saved: the long stair is still folded")
	var cliff := _on_cliff(level, evidence.checkpoints[0])
	Walk.walk(cliff, [1160,-64]); Walk.wait_ticks(cliff, 30)
	_check(not cliff.can_commit() and cliff.snapshot().players.p0.surface_id == "cliff", "Waiting at the lip without dropping cannot be saved")
	var closed := Simulation.new()
	closed.reset(level, "go-on-ahead", evidence.checkpoints[0])
	Walk.walk(closed, [-1104,200]); Walk.tap(closed); Walk.tap(closed)
	Walk.walk(closed, [-1216,200])
	for _tick in range(40): closed.step({"move_z": -1.0})
	_check(not bool(closed.snapshot().levers.get("garden-gate", false)) and not bool(closed.snapshot().bridges["cliff-steps"]) and int(closed.snapshot().players.p0.height) == 0 and not closed.can_commit(), "With the gate shut, the steps stay folded and nothing can be saved")
	var early := Witness.source(level, "go-on-ahead", evidence.checkpoints[0])
	_check(early.can_commit() and early.snapshot().players.p0.surface_id == "well-floor" and bool(early.snapshot().levers["garden-gate"]), "Saving needs the friend on the rope in the well with the gate on")
	var mid := Simulation.new()
	mid.reset(level, "back-for-you", evidence.checkpoints[1])
	Witness._route(mid, Witness.TOWER_OUT); Walk.tap(mid); Walk.wait_ticks(mid, 20)
	_check(not mid.can_commit() and bool(mid.snapshot().bridges["well-ladder"]), "Stage two cannot be saved at the winch: the step by the bell is the place to wait")

func _receiver_never_stranded(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var prior: Dictionary = evidence.pairs[0].a
	# Rush straight to the stair: it is folded, so the climber waits on the grass.
	var sim := Simulation.new()
	sim.reset(level, "go-on-ahead", evidence.checkpoints[0], prior, "b")
	Witness._route(sim, Witness.GARDEN_PATH)
	var blocked := true
	for _tick in range(10):
		if bool(sim.snapshot().bridges["long-stair"]): break
		sim.step({"move_z": -1.0})
		blocked = blocked and int(sim.snapshot().players.p1.height) == 0
	_check(blocked, "Before the friend drops in, the folded stair holds the climber on the grass")
	Witness.wait_for_route(sim, "long-stair")
	var opened_at: int = sim.tick
	var open_after := true
	Walk.walk(sim, [976,-96])
	Walk.walk(sim, [1160,-96])
	Walk.tap(sim)
	while not sim.finished:
		open_after = open_after and bool(sim.snapshot().bridges["long-stair"])
		sim.step({})
	_check(open_after and sim.complete and opened_at <= int(prior.duration_ticks), "Once the friend lands, the long stair stays open to the end: nobody is stranded")
	# Past the friend's recording the frozen spirit keeps holding the rope.
	var late := Simulation.new()
	late.reset(level, "go-on-ahead", evidence.checkpoints[0], prior, "b")
	Walk.wait_ticks(late, int(prior.duration_ticks) + 60)
	_check(bool(late.snapshot().bridges["long-stair"]) and bool(late.snapshot().hold_pads["bucket-rope"]), "After the recording ends the frozen friend still holds the rope")

func _rope_walk_holds_under_ghost(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var first := Simulation.new()
	first.reset(level, "back-for-you", evidence.checkpoints[1])
	var initial: Dictionary = first.snapshot()
	_check(initial.hold_pads["still-holding"] and initial.bridges["rope-walk-west"] and initial.bridges["rope-walk-east"] and not initial.bridges["well-ladder"], "From the first tick, the friend still holding on keeps the rope-walk open")
	_check(_role_badge(initial, "p0") == "Waiting", "The friend in the well is shown waiting")
	# Replay the accepted receiver turn tick by tick, checking both spans each tick.
	var held := true
	var ghost_on_rope := false
	var climbed := false
	for record: Dictionary in [evidence.pairs[1].b] + ([evidence.long_b] if evidence.has("long_b") else []):
		var sim := Simulation.new()
		sim.reset(level, "back-for-you", evidence.checkpoints[1], evidence.pairs[1].a, "b")
		for frame: Dictionary in Simulation.expand_recording_inputs(record):
			var state: Dictionary = sim.step(frame)
			held = held and state.bridges["rope-walk-west"] and state.bridges["rope-walk-east"]
			ghost_on_rope = ghost_on_rope or str(state.players.p1.surface_id).begins_with("rope-walk")
			climbed = climbed or str(state.players.p0.surface_id) == "well-ladder"
		held = held and sim.complete
	_check(held and ghost_on_rope and climbed, "The rope-walk never closes under the ghost, before or after the friend climbs out")

func _long_receiver(evidence: Dictionary) -> void:
	# Rules 9 keep comfort's longer second turn: a receiver past 900 ticks verifies.
	var level: Dictionary = evidence.definition
	var sim := Simulation.new()
	sim.reset(level, "back-for-you", evidence.checkpoints[1], evidence.pairs[1].a, "b")
	Walk.wait_ticks(sim, 930)
	Walk.walk(sim, [1180,16]); Walk.walk(sim, [1592,16]); Walk.tap(sim)
	Witness.wait_for_completion(sim)
	var record: Dictionary = sim.export_recording()
	_check(sim.complete and int(record.duration_ticks) > 900 and Simulation.verify_recording(level, _json(record), _json(evidence.checkpoints[1]), _json(evidence.pairs[1].a)).valid, "A rules 9 receiver turn longer than 900 ticks verifies (%d ticks)" % int(record.get("duration_ticks", 0)))
	evidence["long_b"] = record

func _on_cliff(level: Dictionary, checkpoint: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	sim.reset(level, "go-on-ahead", checkpoint)
	Walk.walk(sim, [-1104,200]); Walk.tap(sim)
	Witness._route(sim, Witness.CLIFF_PATH)
	return sim

func _clone_turn(level: Dictionary, base: RefCounted) -> RefCounted:
	var copy := Simulation.new()
	copy.reset(level, base.stage.id, base._checkpoint, base._prior, base.role)
	for frame: Dictionary in Simulation.expand_recording_inputs(base.export_recording()): copy.step(frame)
	return copy

func _role_badge(state: Dictionary, slot: String) -> String:
	return "You" if slot == str(state.active_slot) else "Memory" if state.players[slot].get("ghost", false) else "Waiting"

func _inside_pad(player: Dictionary) -> bool:
	return Vector2(int(player.x) - 1160, int(player.z)).length() <= 48.0

func _inside(player: Dictionary, rect: Array, margin: int) -> bool:
	return int(player.x) >= rect[0] + margin and int(player.x) <= rect[2] - margin and int(player.z) >= rect[1] + margin and int(player.z) <= rect[3] - margin

func _circle_touches(player: Dictionary, rect: Array) -> bool:
	var closest := Vector2i(clampi(int(player.x), rect[0], rect[2]), clampi(int(player.z), rect[1], rect[3]))
	return Vector2i(int(player.x), int(player.z)).distance_squared_to(closest) < RADIUS * RADIUS

func _bound(value: Dictionary, limit: int, label: String) -> void:
	var stack: Array = [{"value": value, "depth": 0}]
	var nodes := 0
	var depth := 0
	while not stack.is_empty():
		var current: Dictionary = stack.pop_back()
		nodes += 1
		depth = maxi(depth, current.depth)
		if current.value is Dictionary:
			for child: Variant in current.value.values(): stack.append({"value": child, "depth": current.depth + 1})
		elif current.value is Array:
			for child: Variant in current.value: stack.append({"value": child, "depth": current.depth + 1})
	_check(JSON.stringify(value).to_utf8_buffer().size() <= limit and nodes <= 32000 and depth <= 16, "Real " + label + " fits the comfort byte/node/depth limits")

func _write_fixtures(evidence: Dictionary) -> void:
	_write("the-wishing-well-definition", evidence.definition)
	_write("the-wishing-well-initial-checkpoint", evidence.checkpoints[0])
	for index in range(2):
		var id: String = evidence.definition.stages[index].id
		_write(id + "-a", evidence.pairs[index].a)
		_write(id + "-b", evidence.pairs[index].b)
		_write(id + "-checkpoint", evidence.checkpoints[index + 1])
	_write("the-wishing-well-final-checkpoint", evidence.checkpoints[2])
	if evidence.has("long_b"): _write("back-for-you-b-long", evidence.long_b)

func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://tests/fixtures/cooperative/" + name + ".json", FileAccess.WRITE)
	_check(file != null, "Fixture destination is writable")
	if file != null:
		file.store_string(JSON.stringify(value, "\t") + "\n")
		file.close()

func _json(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
