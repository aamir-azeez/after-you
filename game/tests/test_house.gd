extends SceneTree
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const House = preload("res://core/cooperative/house_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Witness = preload("res://tests/house_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var evidence := Witness.chapter()
	_check(evidence.error.is_empty(), "House walkthrough uses real controls: " + evidence.error)
	if evidence.error.is_empty():
		_preservation()
		_pairs(evidence)
		_repurpose_weight(evidence)
		_hatch_and_recovery(evidence)
		_bench_collision(evidence)
		_ownership(evidence)
		_off_center_prefix(evidence)
		if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args(): _write_fixtures(evidence)
	print("AFTER YOU HOUSE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _preservation() -> void:
	_check(Canonical.digest(Catalog.definition("high-and-low")) == "6aa907e802c92445745a6452c6ec0850dd8e98724e689b58a8ec82915fb08956", "Published free chapter definition remains unchanged")
	_check(Canonical.digest(Catalog.definition("rolling-home")) == "d6aaa6006597dd5e4ce4dbc641d94c81c2ab17c55bd80b50c6a240e0e91cff87", "Published paid chapter definition remains unchanged")
	var level := House.definition()
	_check(level.schema_version == 6 and level.simulation_version == 6 and level.stages.size() == 2 and level.premium, "House composes the same bounded simulation6 rules and paid-host access")

func _pairs(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	for index in range(2):
		var pair: Dictionary = evidence.pairs[index]
		var previous: Dictionary = evidence.checkpoints[index]
		var checkpoint: Dictionary = evidence.checkpoints[index + 1]
		_check(pair.a.player_slot == ("p0" if index == 0 else "p1") and pair.b.player_slot != pair.a.player_slot, "House partners exchange source responsibility")
		_check(pair.a.duration_ticks <= 650, "Source route preserves a practical margin below the900tick limit")
		_check(pair.b.duration_ticks <= 540, "Real accepted route leaves at least12seconds of the900tick limit")
		for role: String in ["a", "b"]:
			var record: Dictionary = pair[role]
			var prior: Dictionary = pair.a if role == "b" else {}
			var verified := Simulation.verify_recording(level, _json(record), _json(previous), _json(prior))
			_check(verified.valid, "House recording independently verifies across JSON: " + record.stage_id + "/" + role)
			var replay := Simulation.new()
			_check(replay.reset(level, record.stage_id, previous, prior, role), "Replay begins from exact accepted checkpoint")
			var frames := Simulation.expand_recording_inputs(record)
			var middle := frames.size() / 2
			for frame: Dictionary in frames.slice(0, middle): replay.step(frame)
			var draft := replay.export_recording()
			var resumed := Simulation.new()
			resumed.reset(level, record.stage_id, previous, prior, role)
			for frame: Dictionary in Simulation.expand_recording_inputs(draft): resumed.step(frame)
			_check(replay.state_hash() == resumed.state_hash(), "Saved middle-of-turn input reconstructs exact state")
			for frame: Dictionary in frames.slice(middle): resumed.step(frame)
			_check(Canonical.same(resumed.export_recording(), record), "Resumed house turn retains exact recording hashes")
			_bound(record, 49152, "recording")
		var derived := Simulation.derive_checkpoint(level, previous, pair.a, pair.b)
		_check(derived.valid and Canonical.same(derived.checkpoint, checkpoint) and Simulation.verify_checkpoint(level, _json(checkpoint)).valid, "Full accepted house proof derives and verifies")
		_bound(checkpoint, 229376, "checkpoint")
		_bound({"schema_version": 2, "recording": pair.b, "checkpoint": checkpoint}, 327680, "turn packet")
		var tampered: Dictionary = pair.a.duplicate(true)
		tampered.actions[0].x = -100 if tampered.actions[0].x != -100 else 100
		tampered.recording_hash = Simulation.recording_hash(tampered)
		_check(not Simulation.verify_recording(level, tampered, previous).valid, "Rehashed house inputs cannot invent a valid replay outcome")
		print("House stage %s: A=%dticks B=%dticks" % [level.stages[index].id, pair.a.duration_ticks, pair.b.duration_ticks])
	var final: Dictionary = evidence.checkpoints[2]
	_check(final.stage_index == 2 and final.next_stage_id.is_empty(), "Exactly two accepted pairs finish the house")
	var ball: Dictionary = final.mechanisms.props["house-ball"]
	_check(ball.status == "claimed" and ball.holder_slot == "p0" and ball.socket_id.is_empty() and ball.x == 592 and ball.z == 0, "Finale leaves the claimed ball as a weight instead of fitting a cradle")
	_check(final.players.p0.x == 960 and final.players.p0.z == 112, "Receiver leaves the weighted ball to ring the sunroom bell")
	_check(not Simulation.verify_checkpoint(Catalog.definition("rolling-home"), final).valid, "House proof cannot be replayed as a published paid chapter")

func _repurpose_weight(evidence: Dictionary) -> void:
	var sim := Simulation.new()
	sim.reset(evidence.definition, "open-the-house", evidence.checkpoints[0])
	Walk.walk(sim, [-320,112]); Walk.wait_ticks(sim, 15)
	_check(sim.snapshot().bridges["workshop-entry"] and not sim.can_commit() and not sim.snapshot().bridges["loft-stairs"], "First plate opens entry but cannot substitute for final source readiness")
	for point: Array in [[-320,176],[-224,176],[-224,112],[32,112],[32,144]]: Walk.walk(sim, point)
	Walk.tap(sim)
	_check(sim.snapshot().bridges["workshop-return"] and not sim.can_commit(), "Workshop lever opens the return before the second plate is weighted")
	for point: Array in [[32,112],[-256,112],[-320,112]]: Walk.walk(sim, point)
	_check(not sim.snapshot().hold_pads["entry-weight"] and sim.snapshot().bridges["workshop-entry"], "Lever keeps the original doorway open when its plate is released")
	for point: Array in [[-320,160],[-352,160],[-352,144],[-352,-80]]: Walk.walk(sim, point)
	Walk.wait_ticks(sim, 15)
	_check(sim.can_commit() and sim.snapshot().hold_pads["stair-weight"] and sim.snapshot().bridges["loft-stairs"], "Repurposing the same ball opens the partner's upstairs route")
	_check(evidence.checkpoints[1].mechanisms.latched_bridges == ["loft-stairs", "workshop-entry", "workshop-return"], "First accepted pair preserves both doorways and stairs")

func _hatch_and_recovery(evidence: Dictionary) -> void:
	var sim := Simulation.new()
	sim.reset(evidence.definition, "the-room-below", evidence.checkpoints[1])
	Walk.walk(sim, [560,-128]); Walk.walk(sim, [560,80]); Walk.walk(sim, [496,80])
	_check(sim.snapshot().players.p1.height == 160 and not sim.can_commit(), "Closed hatch stays safe and cannot authorize an unfinished source")
	Walk.walk(sim, [560,80]); Walk.tap(sim); Walk.walk(sim, [496,80])
	_check(sim.snapshot().players.p1.height == 0 and sim.snapshot().players.p1.surface_id == "lower-hall", "Lever opens a real lower-hall landing")
	for point: Array in [[496,0],[128,0],[128,-112],[576,-112]]: Walk.walk(sim, point)
	_check(sim.snapshot().players.p1.height == 160 and not sim.finished, "Previously latched stairs remain a recovery route after dropping")

func _bench_collision(evidence: Dictionary) -> void:
	var sim := Simulation.new()
	sim.reset(evidence.definition, "the-room-below", evidence.checkpoints[1])
	for point: Array in [[560,-128],[560,80]]: Walk.walk(sim, point)
	Walk.tap(sim)
	for point: Array in [[496,80],[496,0],[128,0]]: Walk.walk(sim, point)
	for _tick in range(12): sim.step({"move_x": -1.0})
	_check(sim.snapshot().players.p1.x == 92, "Visible bench edge80 blocks the player's12cm body at92")
	for point: Array in [[128,0],[128,-112],[-256,-112],[-256,-192],[-400,-192],[-400,-112],[-384,-112],[0,-112],[0,-160],[32,-160],[32,-144]]: Walk.walk(sim, point)
	for _tick in range(18): sim.step({"move_z": 1.0})
	_check(sim.snapshot().props["house-ball"].z == -36 and sim.snapshot().players.p1.z == -68 and not sim.can_commit(), "Ball radius20 blocks the direct route through the bench; unfinished detour cannot be accepted")

func _ownership(evidence: Dictionary) -> void:
	var sim := Simulation.new()
	sim.reset(evidence.definition, "open-the-house", evidence.checkpoints[0], evidence.pairs[0].a, "b")
	Walk.walk(sim, [-224,-112]); Walk.walk(sim, [-224,112])
	Walk.wait_ticks(sim, maxi(0, int(evidence.pairs[0].a.duration_ticks) - sim.tick))
	for _tick in range(60): sim.step({"move_x": 1.0})
	_check(sim.snapshot().bridges["workshop-entry"] and sim.snapshot().players.p1.x < -192, "An open p0 doorway cannot be used by p1")
	var prior: Dictionary = evidence.pairs[1].a
	var hash_before := Canonical.digest(prior)
	sim = Witness.receiver(evidence.definition, "the-room-below", evidence.checkpoints[1], prior)
	_check(sim.complete and Canonical.digest(prior) == hash_before, "Claimed ball movement never rewrites the earlier partner recording")

func _off_center_prefix(evidence: Dictionary) -> void:
	var first := Witness.source(evidence.definition, "open-the-house", evidence.checkpoints[0], 8)
	Walk.walk(first, [-272,-72])
	var a: Dictionary = first.export_recording()
	var second := Witness.receiver(evidence.definition, "open-the-house", evidence.checkpoints[0], a, [560,-144])
	var prefix := Simulation.derive_checkpoint(evidence.definition, evidence.checkpoints[0], a, second.export_recording())
	_check(first.can_commit() and second.complete and prefix.valid, "Off-centre ball and accepted poses produce a native-proven first checkpoint")
	if not prefix.valid: return
	_check(prefix.checkpoint.mechanisms.props["house-ball"].z == -104, "First accepted ball remains8cm off the stair plate centre")
	var next_a := Witness.source(evidence.definition, "the-room-below", prefix.checkpoint, 0, 8)
	_check(next_a.snapshot().props["house-ball"].x == 472 and next_a.snapshot().props["house-ball"].status == "offered", "Source offers the ball8cm off the lower-hall marker after the bench turn")
	var next_b := Witness.receiver(evidence.definition, "the-room-below", prefix.checkpoint, next_a.export_recording())
	_check(next_a.can_commit() and next_b.complete, "Second pair works from legitimate off-centre predecessor poses without teleporting")
	var final := Simulation.derive_checkpoint(evidence.definition, prefix.checkpoint, next_a.export_recording(), next_b.export_recording())
	_check(final.valid and Simulation.verify_checkpoint(evidence.definition, final.checkpoint).valid, "Off-centre ball path keeps the full native-verified proof chain")

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
	_check(JSON.stringify(value).to_utf8_buffer().size() <= limit and nodes <= 24000 and depth <= 16, "Real house " + label + " fits unchanged byte/node/depth limits")

func _write_fixtures(evidence: Dictionary) -> void:
	_write("a-house-for-two-definition", evidence.definition)
	_write("a-house-for-two-initial-checkpoint", evidence.checkpoints[0])
	for index in range(2):
		var id: String = evidence.definition.stages[index].id
		_write(id + "-a", evidence.pairs[index].a)
		_write(id + "-b", evidence.pairs[index].b)
		_write(id + "-checkpoint", evidence.checkpoints[index + 1])
	_write("a-house-for-two-final-checkpoint", evidence.checkpoints[2])

func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://tests/fixtures/cooperative/" + name + ".json", FileAccess.WRITE)
	_check(file != null, "House fixture destination is writable")
	if file != null:
		file.store_string(JSON.stringify(value, "\t") + "\n")
		file.close()

func _json(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
