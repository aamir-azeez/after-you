extends SceneTree

const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Witness = preload("res://tests/cooperative_witness.gd")
var checks := 0
var failures := 0
var chapters: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	# The House has its own route/prop expectations in test_house.gd.
	for key: String in ["high-and-low@1", "rolling-home@1"]:
		var evidence := Witness.chapter(key)
		_check(evidence.error.is_empty(), "Real control walkthrough completes " + key + ": " + evidence.error)
		if not evidence.error.is_empty(): continue
		chapters[key] = evidence
		_chapter(evidence)
		_integrity(evidence)
		_nonviable(evidence)
	if chapters.size() == 2:
		_cross_chapter()
		_ball_authority(chapters["rolling-home@1"])
		_height_and_owned_routes(chapters["high-and-low@1"])
	_check(chapters.size() == 2, "All four new stages have independent successful A and B inputs")
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args(): _write_fixtures()
	print("AFTER YOU COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	_check(level.schema_version == 6 and level.simulation_version == 6 and level.stages.size() == 2, "New chapters bind exactly two version-six stages")
	_check(level.premium == (level.id == "rolling-home"), "Only Rolling Home requires Full Journey")
	_check(Simulation.verify_checkpoint(level, _json(evidence.checkpoints[0])).valid, "Exact initial checkpoint survives the network JSON boundary")
	for index in range(2):
		var pair: Dictionary = evidence.pairs[index]
		var previous: Dictionary = evidence.checkpoints[index]
		var next: Dictionary = evidence.checkpoints[index + 1]
		_check(pair.a.player_slot == ("p0" if index == 0 else "p1") and pair.b.player_slot != pair.a.player_slot, "A/B roles swap physical slots between stages")
		_check(pair.a.checkpoint_hash == previous.checkpoint_hash and pair.b.source_recording_hash == pair.a.recording_hash, "Both inputs bind the exact predecessor and source")
		for role: String in ["a", "b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			var record: Dictionary = pair[role]
			var checked := Simulation.verify_recording(level, _json(record), _json(previous), _json(prior))
			_check(checked.valid, "Actual " + record.stage_id + "/" + role + " verifies independently")
			_check(record.duration_ticks > 0 and record.duration_ticks < Simulation.MAX_TICKS, "Generous authored walkthrough fits the fixed turn bound")
			var replay := Simulation.new()
			_check(replay.reset(level, record.stage_id, previous, prior, role), "Replay begins from verified physical positions")
			_check(Canonical.same(_physical(replay.snapshot().players.p0), previous.players.p0) and Canonical.same(_physical(replay.snapshot().players.p1), previous.players.p1), "Starting a later stage never teleports either player")
			var frames := Simulation.expand_recording_inputs(record)
			var midway := maxi(1, frames.size() / 2)
			for frame: Dictionary in frames.slice(0, midway): replay.step(frame)
			var draft: Dictionary = replay.export_recording()
			var resumed := Simulation.new()
			_check(resumed.reset(level, record.stage_id, previous, prior, role), "Draft resumes against the same source and checkpoint")
			for frame: Dictionary in Simulation.expand_recording_inputs(draft): resumed.step(frame)
			_check(resumed.state_hash() == replay.state_hash(), "Reconstruction resumes the exact middle-tick state")
			for frame: Dictionary in frames.slice(midway): resumed.step(frame)
			_check(Canonical.same(resumed.export_recording(), record), "Resumed inputs retain every replay hash and outcome")
			_bound(record, 49152, "recording")
		var derived := Simulation.derive_checkpoint(level, _json(previous), _json(pair.a), _json(pair.b))
		_check(derived.valid and Canonical.same(derived.checkpoint, next), "Each complete pair advances exactly one deterministic checkpoint")
		_check(Simulation.verify_checkpoint(level, _json(next)).valid, "Full nested proof independently verifies at each checkpoint")
		_check(next.stage_index == index + 1 and next.next_stage_id == (level.stages[1].id if index == 0 else ""), "Only the second verified pair completes its own chapter")
		_bound(next, 229376, "checkpoint")
		_bound({"schema_version": 2, "recording": pair.b, "checkpoint": next}, 327680, "turn packet")

func _integrity(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var initial: Dictionary = evidence.checkpoints[0]
	var first: Dictionary = evidence.pairs[0].a
	var bad := initial.duplicate(true)
	bad.players.p0.x += 8
	bad.checkpoint_hash = Catalog.checkpoint_hash(bad)
	_check(not Simulation.verify_checkpoint(level, bad).valid, "Rehashing a fabricated initial position does not grant access")
	bad = first.duplicate(true)
	bad.actions[0].x = -100 if bad.actions[0].x != -100 else 100
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(level, bad, initial).valid, "Rehashed input tampering cannot retain accepted replay hashes")
	bad = first.duplicate(true)
	bad.outcome.source_ready = not bad.outcome.source_ready
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(level, bad, initial).valid, "Rehashed invented source outcome fails deterministic replay")
	for field: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		bad = first.duplicate(true)
		bad[field] += 1
		bad.recording_hash = Simulation.recording_hash(bad)
		_check(not Simulation.verify_recording(level, bad, initial).valid, "Unsupported version is held: " + field)
	bad = evidence.pairs[0].b.duplicate(true)
	bad.source_recording_hash = "0".repeat(64)
	bad.recording_hash = Simulation.recording_hash(bad)
	_check(not Simulation.verify_recording(level, bad, initial, first).valid, "Receiver cannot substitute its source dependency")
	bad = evidence.checkpoints[1].duplicate(true)
	bad.players.p1.x += 8
	bad.checkpoint_hash = Catalog.checkpoint_hash(bad)
	_check(not Simulation.verify_checkpoint(level, bad).valid, "Rehashed checkpoint must still match actual pair endpoints")
	bad = level.duplicate(true)
	bad.stages[0].version += 1
	_check(not Simulation.new().reset(bad, level.stages[0].id, initial), "Unknown chapter definitions cannot execute by matching a name")
	_check(not Simulation.new().reset(level, level.stages[1].id, initial), "A later stage cannot skip the preceding proof")

func _nonviable(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	for index in range(2):
		var previous: Dictionary = evidence.checkpoints[index]
		var stage_id: String = level.stages[index].id
		var late := Simulation.new()
		_check(late.reset(level, stage_id, previous), "Deadline test starts from a legitimate prefix")
		Witness.wait_ticks(late, Simulation.MAX_TICKS - 1)
		_check(late.tick == Simulation.MAX_TICKS - 1 and not late.finished, "New chapter recording remains live beyond the earlier twenty-second ceiling")
		Witness.tap(late)
		_check(not late.can_commit(), "An idle or impossible last-tick source cannot be committed")
		_check(not Simulation.new().reset(level, stage_id, previous, late.export_recording(), "b"), "Invalid source cannot initialize a receiver")
	var short := Simulation.new()
	short.reset(level, level.stages[0].id, evidence.checkpoints[0])
	if level.id == "high-and-low":
		Witness.walk(short, [-544, 112]); Witness.tap(short)
		Witness.walk(short, [-448, -128])
		_check(not short.can_commit(), "The first physical pad contact does not skip the authored hold")

func _cross_chapter() -> void:
	var paid: Dictionary = chapters["rolling-home@1"]
	var free: Dictionary = chapters["high-and-low@1"]
	_check(not Simulation.verify_recording(free.definition, paid.pairs[0].a, free.checkpoints[0]).valid, "A valid paid-chapter recording cannot execute in the free chapter")
	_check(not Simulation.verify_checkpoint(paid.definition, free.checkpoints[2]).valid, "Complete checkpoints cannot cross chapter identities")
	_check(not Simulation.new().reset(paid.definition, paid.definition.stages[0].id, free.checkpoints[0]), "A foreign starting checkpoint is rejected before simulation")

func _ball_authority(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var previous: Dictionary = evidence.checkpoints[1]
	var first: Dictionary = evidence.pairs[1].a
	var b := Simulation.new()
	b.reset(level, "bring-it-home", previous, first, "b")
	Witness.tap(b)
	_check(b.snapshot().props["round-ball"].holder_slot != "p0" and not b.complete, "A receiver cannot claim an unoffered ball remotely")
	var digest := Canonical.digest(first)
	b = Witness.receiver(level, "bring-it-home", previous, first)
	_check(b.complete and b.snapshot().props["round-ball"].socket_id == "home-cradle", "The exact offered ball reaches its real home cradle")
	_check(Canonical.digest(first) == digest, "Receiver takeover never rewrites the earlier source recording")
	var late := Simulation.new()
	late.reset(level, "bring-it-home", previous)
	Witness.wait_ticks(late, 360)
	for frame: Dictionary in Simulation.expand_recording_inputs(first): late.step(frame)
	_check(not late.can_commit() and not Simulation.new().reset(level, "bring-it-home", previous, late.export_recording(), "b"), "A delayed offer reserves the real turning-route time and rejects an impossible receiver deadline")

func _height_and_owned_routes(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var initial: Dictionary = evidence.checkpoints[0]
	var owner := Simulation.new()
	owner.reset(level, "down-and-around", evidence.checkpoints[1], evidence.pairs[1].a, "b")
	Witness.walk(owner, [-288, 0])
	for _tick in range(60): owner.step({"move_x": 1.0})
	_check(owner.snapshot().bridges.get("blue-stair", false) and owner.snapshot().players.p0.height == 0 and owner.snapshot().players.p0.x < -240, "The red player cannot borrow already-open blue stairs")
	var climber := Simulation.new()
	climber.reset(level, "upper-path", initial, evidence.pairs[0].a, "b")
	Witness.walk(climber, [-160, 0])
	_check(climber.snapshot().players.p1.height > 0 and climber.snapshot().players.p1.height < 160, "Actual stair movement passes through an intermediate elevation")
	var ghost := Simulation.new()
	ghost.reset(level, "upper-path", initial, evidence.pairs[0].a, "b")
	Witness.walk(ghost, [-448, -128])
	Witness.wait_ticks(ghost, maxi(0, int(evidence.pairs[0].a.duration_ticks) - ghost.tick))
	_check(ghost.snapshot().players.p1.x == ghost.snapshot().players.p0.x and ghost.snapshot().players.p1.z == ghost.snapshot().players.p0.z, "The partner's real recorded position is nonblocking when both paths meet")
	var early := Simulation.new()
	early.reset(level, "down-and-around", evidence.checkpoints[1])
	Witness.walk(early, [240, -128]); Witness.walk(early, [240, 48])
	_check(early.snapshot().players.p1.height == 160 and not early.can_commit(), "The closed hatch keeps the player safely upstairs until its lever is pulled")
	_check(not Simulation.new().reset(level, "down-and-around", evidence.checkpoints[1], early.export_recording(), "b"), "An unfinished hatch attempt cannot authorize the partner's lower crossing")
	var falling := Simulation.new()
	falling.reset(level, "down-and-around", evidence.checkpoints[1])
	Witness.walk(falling, [240, -128]); Witness.tap(falling)
	Witness.walk(falling, [240, 48])
	var landed: Dictionary = falling.snapshot().players.p1
	_check(landed.height == 0 and landed.surface_id == "lower-ledge" and absi(landed.x - 240) <= 1, "The opened drop lands at the real lower surface instead of swapping players")
	Witness.walk(falling, [240, -128])
	_check(falling.snapshot().players.p1.height == 0, "A lower player cannot regain the loft by walking under it")

func _bound(value: Dictionary, byte_limit: int, label: String) -> void:
	var stack: Array = [{"value": value, "depth": 0}]
	var nodes := 0
	var max_depth := 0
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		nodes += 1
		max_depth = maxi(max_depth, int(item.depth))
		if item.value is Dictionary:
			for child: Variant in item.value.values(): stack.append({"value": child, "depth": item.depth + 1})
		elif item.value is Array:
			for child: Variant in item.value: stack.append({"value": child, "depth": item.depth + 1})
	_check(JSON.stringify(value).to_utf8_buffer().size() <= byte_limit and nodes <= 24000 and max_depth <= 16, "Real " + label + " fits backend byte/node/depth admission bounds")

func _write_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures/cooperative")
	for evidence: Dictionary in chapters.values():
		var level: Dictionary = evidence.definition
		_write(level.id + "-definition", level)
		_write(level.id + "-initial-checkpoint", evidence.checkpoints[0])
		for index in range(2):
			var stage_id: String = level.stages[index].id
			_write(stage_id + "-a", evidence.pairs[index].a)
			_write(stage_id + "-b", evidence.pairs[index].b)
			_write(stage_id + "-checkpoint", evidence.checkpoints[index + 1])
		_write(level.id + "-final-checkpoint", evidence.checkpoints[2])

func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://tests/fixtures/cooperative/" + name + ".json", FileAccess.WRITE)
	_check(file != null, "Fixture destination is writable")
	if file != null:
		file.store_string(JSON.stringify(value, "\t") + "\n")
		file.close()

func _json(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func _physical(player: Dictionary) -> Dictionary:
	return {"x": player.x, "z": player.z, "height": player.height, "surface_id": player.surface_id}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
