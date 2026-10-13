extends SceneTree
## turn-of-the-tide@1 sizes against the server limits, two ways.
## Full length: in both stages the recorder's input changes on every tick up
## to the first turn's cap and the receiver's up to ten ticks before its own,
## so every tick is its own action entry. The turns are the real LOW / boom routes, replayed with a
## one-step wobble on the idle axis that never moves anyone, then derived
## through the full proof. Most of those entries carry one-digit axis values.
## Structural bound: the derived stage-2 checkpoint with every action entry of
## its four recordings rewritten to the widest form ({ticks:1, x:-100,
## z:-100 or -99, action:false}), one entry a tick for each turn's whole cap.
## The backend's limits are structural, so this needs no replay.
## The turn caps come from the definition (2,700 ticks for A, 3,000 for B).
## Limits, measured as the backend does (JSON bytes and value count), are the
## published comfort bounds grown by the same factor as the longest turn
## (protocol-physical-recording.ts scaledLimits):
##   checkpoint: MAX_CHECKPOINT_BYTES 229,376 and 24,000 values (protocol-relay.ts boundedValue);
##   comfort recording: 65,536 bytes and 24,000 values;
##   receiver turn body: MAX_V2_BODY_BYTES 327,680 and 32,000 values (boundedTurnValue).
const Simulation = preload("res://core/journey/simulation.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PUBLISHED := {"recording_bytes": 65536, "recording_values": 24000, "checkpoint_bytes": 229376, "checkpoint_values": 24000, "turn_body_bytes": 327680, "turn_body_values": 32000}
## The same bounds at 2,700 and 3,000 ticks, as the backend test pins them.
const SCALED := {"recording_bytes": 196608, "recording_values": 72000, "checkpoint_bytes": 688128, "checkpoint_values": 72000, "turn_body_bytes": 983040, "turn_body_values": 96000}
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var a_ticks := 0
var b_ticks := 0
## B rings this many ticks before its cap.
var ring_tick := 0
var limits: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	a_ticks = Runtime.turn_ticks(level, Witness.RULES, "a")
	b_ticks = Runtime.turn_ticks(level, Witness.RULES, "b")
	ring_tick = b_ticks - 10
	limits = _scaled()
	_check(a_ticks == 2700 and b_ticks == 3000 and Canonical.same(limits, SCALED), "The definition's 2,700 and 3,000 ticks scale every bound by 3 (%d, %d, %s)" % [a_ticks, b_ticks, str(limits)])
	var first := _stage(Witness.SET, initial, Witness.a_routes()["low"], Witness.b_routes()["low"])
	if not first.is_empty():
		var second := _stage(Witness.SLACK, first.checkpoint, Witness.p1_home("low") + Witness.p1_way("low", "boom"), Witness.p0_way("low", "boom"))
		if not second.is_empty():
			var checkpoint: Dictionary = second.checkpoint
			var size := _bytes(checkpoint)
			var values := _values(checkpoint)
			_check(size <= limits.checkpoint_bytes and values <= limits.checkpoint_values, "The full-length stage-2 checkpoint fits: %d bytes of %d, %d values of %d" % [size, limits.checkpoint_bytes, values, limits.checkpoint_values])
			# The largest body a receiver can send: the completion proof's four
			# records plus its own record again.
			var body := {"checkpoint": checkpoint, "recording": second.b}
			var turn_size := _bytes(body)
			var turn_values := _values(body)
			_check(turn_size <= limits.turn_body_bytes and turn_values <= limits.turn_body_values, "A full-length receiver turn body (four records plus the receiver's again) fits: %d bytes of %d, %d values of %d" % [turn_size, limits.turn_body_bytes, turn_values, limits.turn_body_values])
			print("TIDE bytes checkpoint=%d values=%d turn=%d values=%d" % [size, values, turn_size, turn_values])
			_structural(checkpoint)
	print("TURN OF THE TIDE BYTES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## One stage at full length: A wobbles to its cap, B rings ten ticks before its own.
func _stage(stage_id: String, checkpoint: Dictionary, a_ops: Array, b_ops: Array) -> Dictionary:
	var clean_a := Witness.source(level, stage_id, checkpoint, a_ops, 0, Callable(), true)
	var frames := _wobble(Simulation.expand_recording_inputs(clean_a.export_recording()))
	while frames.size() < a_ticks: frames.append(_idle(frames.size()))
	var a := _play(stage_id, checkpoint, {}, frames)
	_check(a.can_commit() and a.finished and a.tick == a_ticks, "%s: A at the %d-tick cap still commits (%s)" % [stage_id, a_ticks, a.commit_reason()])
	if not a.can_commit(): return {}
	var first: Dictionary = a.export_recording()
	var clean_b := Witness.receiver(level, stage_id, checkpoint, first, b_ops, Callable(), true)
	var ring := int(clean_b.get_meta("ring_tick", -1)) - 1
	_check(clean_b.complete and ring > 0 and ring < ring_tick, stage_id + ": the clean receiver rings")
	if ring <= 0: return {}
	var inputs := Simulation.expand_recording_inputs(clean_b.export_recording())
	var b_frames := _wobble(inputs.slice(0, ring))
	while b_frames.size() < ring_tick - 1: b_frames.append(_idle(b_frames.size()))
	b_frames.append(inputs[ring])
	var b := _play(stage_id, checkpoint, first, b_frames)
	_check(b.complete and b.tick == ring_tick, "%s: B rings at tick %d and completes" % [stage_id, ring_tick])
	if not b.complete: return {}
	var second: Dictionary = b.export_recording()
	for record: Dictionary in [first, second]:
		_check(record.actions.size() >= int(record.duration_ticks) - 30, "%s %s: nearly one action entry per tick (%d of %d)" % [stage_id, record.role, record.actions.size(), record.duration_ticks])
		_check(_bytes(record) <= limits.recording_bytes and _values(record) <= limits.recording_values, "%s %s recording fits: %d bytes of %d, %d values of %d" % [stage_id, record.role, _bytes(record), limits.recording_bytes, _values(record), limits.recording_values])
		print("TIDE bytes %s %s ticks=%d actions=%d bytes=%d values=%d" % [stage_id, record.role, record.duration_ticks, record.actions.size(), _bytes(record), _values(record)])
	var derived := Simulation.derive_checkpoint(level, Witness.json(checkpoint), Witness.json(first), Witness.json(second))
	_check(derived.valid, "%s: the full-length pair derives (%s)" % [stage_id, derived.get("error", "")])
	if not derived.valid: return {}
	return {"a": first, "b": second, "checkpoint": derived.checkpoint}

## Every action entry of the checkpoint's four recordings at the widest form
## and the longest count: an upper bound on any real stage-2 checkpoint.
func _structural(checkpoint: Dictionary) -> void:
	var widest: Dictionary = Witness.json(checkpoint)
	var records: Array = [widest.proof.a, widest.proof.b, widest.proof.checkpoint.proof.a, widest.proof.checkpoint.proof.b]
	for record: Dictionary in records:
		var count := a_ticks if record.role == "a" else b_ticks
		var actions: Array = []
		for index in range(count): actions.append({"action": false, "ticks": 1, "x": -100, "z": -100 if index % 2 == 0 else -99})
		record.actions = actions
		record.duration_ticks = count
	var receiver: Dictionary = widest.proof.b
	var size := _bytes(widest)
	var values := _values(widest)
	_check(size <= limits.checkpoint_bytes and values <= limits.checkpoint_values, "The structural worst stage-2 checkpoint fits: %d bytes of %d, %d values of %d" % [size, limits.checkpoint_bytes, values, limits.checkpoint_values])
	_check(_bytes(receiver) <= limits.recording_bytes and _values(receiver) <= limits.recording_values, "The structural worst receiver recording fits: %d bytes of %d, %d values of %d" % [_bytes(receiver), limits.recording_bytes, _values(receiver), limits.recording_values])
	var body := {"checkpoint": widest, "recording": receiver}
	_check(_bytes(body) <= limits.turn_body_bytes and _values(body) <= limits.turn_body_values, "The structural worst receiver turn body fits: %d bytes of %d, %d values of %d" % [_bytes(body), limits.turn_body_bytes, _values(body), limits.turn_body_values])
	print("TIDE bytes structural checkpoint=%d values=%d receiver=%d values=%d turn=%d values=%d" % [size, values, _bytes(receiver), _values(receiver), _bytes(body), _values(body)])

## The published bounds grown by the longest turn against its published cap
## (900 for A, 1,200 for B), rounded up, as scaledLimits does.
func _scaled() -> Dictionary:
	var factor := maxf(1.0, maxf(float(a_ticks) / 900.0, float(b_ticks) / 1200.0))
	var result: Dictionary = {}
	for key: String in PUBLISHED: result[key] = ceili(float(PUBLISHED[key]) * factor)
	return result

func _play(stage_id: String, checkpoint: Dictionary, first: Dictionary, frames: Array) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = Witness.RULES
	sim._reset_trusted(level, stage_id, checkpoint, first, "a" if first.is_empty() else "b")
	for frame: Dictionary in frames:
		if sim.finished: break
		sim.step(frame)
	return sim

## Every other tick, nudge the axis the walker is not using by one step (0.01),
## or on a two-axis step the larger axis one step toward zero: the quantized
## input differs but the move rounds to the same centimetres (the full-length
## replay below checks that it does).
func _wobble(frames: Array) -> Array:
	var result: Array = []
	for index in range(frames.size()):
		var frame: Dictionary = frames[index].duplicate()
		if index % 2 == 1:
			if is_zero_approx(float(frame.move_z)): frame.move_z = 0.01
			elif is_zero_approx(float(frame.move_x)): frame.move_x = 0.01
			elif absf(float(frame.move_x)) >= absf(float(frame.move_z)): frame.move_x = float(frame.move_x) - signf(float(frame.move_x)) * 0.01
			else: frame.move_z = float(frame.move_z) - signf(float(frame.move_z)) * 0.01
		result.append(frame)
	return result

func _idle(index: int) -> Dictionary:
	return {"move_x": 0.0, "move_z": 0.01 if index % 2 == 1 else 0.0, "interact": false}

func _bytes(value: Dictionary) -> int:
	return JSON.stringify(Canonical.normalized(value)).to_utf8_buffer().size()

## Values as the backend counts them: every object, array and leaf.
func _values(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for key: Variant in value: count += _values(value[key])
	elif value is Array:
		for item: Variant in value: count += _values(item)
	return count

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
